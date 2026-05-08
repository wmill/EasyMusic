import SwiftUI
import AVFoundation
import Combine
import Accelerate

// MARK: - Musical Model

enum MusicalKey: String, CaseIterable, Identifiable {
    case C, G, D, A, E, B, FSharp = "F#", CSharp = "C#", F, Bb = "Bb", Eb = "Eb", Ab = "Ab", Db = "Db", Gb = "Gb", Cb = "Cb"
    var id: String { rawValue }

    // Semitone offset from C for enharmonic spelling aimed at simplicity
    var semitoneOffsetFromC: Int {
        switch self {
        case .C: return 0
        case .G: return 7
        case .D: return 2
        case .A: return 9
        case .E: return 4
        case .B: return 11
        case .FSharp: return 6
        case .CSharp: return 1
        case .F: return 5
        case .Bb: return 10
        case .Eb: return 3
        case .Ab: return 8
        case .Db: return 1 // enharmonic to C#
        case .Gb: return 6 // enharmonic to F#
        case .Cb: return 11 // enharmonic to B
        }
    }
}

struct Scale {
    static let majorIntervals: [Int] = [0, 2, 4, 5, 7, 9, 11]
}

// MARK: - App State

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedKey: MusicalKey? = nil
}

// MARK: - Audio Engine (Procedural Tones)

final class ProceduralAudioEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    // Currently active notes (MIDI -> phase increment)
    private var activeNotes = Set<Int>()
    private var sampleRate: Double = 44100.0
    private var phase: Double = 0
    private var phaseIncrement: Double = 0

    // Simple mix of multiple notes; track frequencies per note
    private var noteFrequencies: [Int: Double] = [:]

    func start() {
        do {
            let output = engine.outputNode
            let format = output.inputFormat(forBus: 0)
            sampleRate = format.sampleRate

            let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self = self else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)

                // Generate audio per frame
                let frames = Int(frameCount)
                if self.activeNotes.isEmpty {
                    for buffer in abl {
                        let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                        vDSP_vclr(ptr, 1, vDSP_Length(frames))
                    }
                    return noErr
                }

                // Precompute increments for each active note
                var increments: [Int: Double] = [:]
                for (note, freq) in self.noteFrequencies where self.activeNotes.contains(note) {
                    increments[note] = (2.0 * .pi * freq) / self.sampleRate
                }

                for buffer in abl {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    for frame in 0..<frames {
                        var sample: Double = 0
                        // Sum sines for all active notes (simple polyphony)
                        for (note, inc) in increments {
                            // Use a separate phase per note by offsetting with note id
                            let localPhase = self.phase + Double(note) * 0.12345
                            sample += sin(localPhase + inc * Double(frame))
                        }
                        ptr[frame] = Float(sample / Double(max(1, increments.count)) * 0.2) // prevent clipping
                    }
                }

                // Advance global phase to keep continuity
                self.phase += (2.0 * .pi * 440.0) / self.sampleRate * Double(frames) * 0.0 // no-op, keep phase stable
                return noErr
            }

            engine.attach(node)
            engine.connect(node, to: output, format: format)
            try engine.start()
            self.sourceNode = node
        } catch {
            print("Audio engine start error: \(error)")
        }
    }

    func stop() {
        engine.stop()
    }

    func play(midiNote: Int) {
        let freq = midiToFrequency(midiNote)
        noteFrequencies[midiNote] = freq
        activeNotes.insert(midiNote)
    }

    func stop(midiNote: Int) {
        activeNotes.remove(midiNote)
        noteFrequencies.removeValue(forKey: midiNote)
    }

    private func midiToFrequency(_ midi: Int) -> Double {
        // A4 = 440Hz at MIDI 69
        return 440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var model = AppModel()
    private let audio = ProceduralAudioEngine()

    var body: some View {
        NavigationStack {
            KeySelectionView()
                .environmentObject(model)
                .navigationDestination(item: $model.selectedKey) { key in
                    JamView(key: key, audio: audio)
                        .environmentObject(model)
                }
        }
        .onAppear { audio.start() }
        .onDisappear { audio.stop() }
    }
}

struct KeySelectionView: View {
    @EnvironmentObject var model: AppModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(MusicalKey.allCases) { key in
                    Button {
                        model.selectedKey = key
                    } label: {
                        Text(key.rawValue)
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .foregroundStyle(.white)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Choose a Key")
    }
}

struct JamView: View {
    let key: MusicalKey
    let audio: ProceduralAudioEngine

    private let intervals = Scale.majorIntervals
    private let baseOctaves = [3, 4, 5] // low, mid, high

    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(0..<7, id: \.self) { degree in
                        PressableKey(
                            title: noteName(for: key, degree: degree, octave: baseOctaves[row]),
                            down: {
                                let midi = midiNote(for: key, degree: degree, octave: baseOctaves[row])
                                audio.play(midiNote: midi)
                            },
                            up: {
                                let midi = midiNote(for: key, degree: degree, octave: baseOctaves[row])
                                audio.stop(midiNote: midi)
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .navigationTitle(key.rawValue)
    }

    private func midiNote(for key: MusicalKey, degree: Int, octave: Int) -> Int {
        let c4 = 60
        let baseCForOctave = c4 + (octave - 4) * 12
        let root = baseCForOctave + key.semitoneOffsetFromC
        return root + intervals[degree]
    }

    private func noteName(for key: MusicalKey, degree: Int, octave: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let semitone = (key.semitoneOffsetFromC + intervals[degree]) % 12
        let name = names[semitone]
        return name
    }
}

struct PressableKey: View {
    let title: String
    let down: () -> Void
    let up: () -> Void

    @State private var isPressed = false

    var body: some View {
        Text(title)
            .font(.largeTitle)
            .frame(maxWidth: .infinity, minHeight: 80)
            .foregroundStyle(.white)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true; down() }
                }
                .onEnded { _ in
                    if isPressed { isPressed = false; up() }
                }
            )
    }

    private var backgroundColor: Color {
        isPressed ? Color.orange : Color(hue: hueFor(title: title), saturation: 0.6, brightness: 0.9)
    }

    private func hueFor(title: String) -> Double {
        // Deterministic hue per note label
        let map: [String: Double] = [
            "C": 0.02, "C#": 0.10, "D": 0.18, "D#": 0.26, "E": 0.34, "F": 0.42, "F#": 0.50, "G": 0.58, "G#": 0.66, "A": 0.74, "A#": 0.82, "B": 0.90
        ]
        return map[title] ?? 0.3
    }
}

#Preview {
    ContentView()
}
