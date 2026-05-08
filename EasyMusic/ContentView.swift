import SwiftUI
import AVFoundation
import Combine

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
    @Published var selectedInstrument: UInt8? = nil
}

// MARK: - Audio Engine (SoundFont Sampler)

final class SamplerAudioEngine {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    func start() {
        do {
            engine.attach(sampler)
            let output = engine.outputNode
            let format = output.inputFormat(forBus: 0)
            engine.connect(sampler, to: output, format: format)

            try engine.start()

            // Load a default preset (Piano) at startup; can be changed later by InstrumentSelectionView
            try loadSoundFont(named: "SGM-v2.01-NicePianosGuitarsBass-V1.2", withExtension: "sf2", preset: UInt8(0), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(0))
        } catch {
            print("Audio engine start error: \(error)")
        }
    }

    func stop() {
        engine.stop()
    }

    func play(midiNote: Int) {
        let velocity: UInt8 = 100
        sampler.startNote(UInt8(clamping: midiNote), withVelocity: velocity, onChannel: 0)
    }

    func stop(midiNote: Int) {
        sampler.stopNote(UInt8(clamping: midiNote), onChannel: 0)
    }

    func loadPreset(_ preset: UInt8, bankMSB: UInt8 = UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8 = 0) {
        do {
            try loadSoundFont(named: "SGM-v2.01-NicePianosGuitarsBass-V1.2", withExtension: "sf2", preset: preset, bankMSB: bankMSB, bankLSB: bankLSB)
        } catch {
            print("Failed to load preset: \(preset) error: \(error)")
        }
    }

    private func loadSoundFont(named name: String, withExtension ext: String, preset: UInt8, bankMSB: UInt8, bankLSB: UInt8) throws {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "SamplerAudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "SoundFont not found: \(name).\(ext)"])
        }
        try sampler.loadSoundBankInstrument(at: url, program: preset, bankMSB: bankMSB, bankLSB: bankLSB)
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var model = AppModel()
    private let audio = SamplerAudioEngine()

    var body: some View {
        NavigationStack {
            InstrumentSelectionView(audio: audio)
                .environmentObject(model)
                .navigationDestination(item: $model.selectedInstrument) { _ in
                    KeySelectionView()
                        .environmentObject(model)
                }
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

struct InstrumentSelectionView: View {
    @EnvironmentObject var model: AppModel
    let audio: SamplerAudioEngine

    // For simplicity, expose a list of common GM program numbers (0-15 for demo). Real SF2 may have many more.
    private let presets: [UInt8] = Array(0...15)

    var body: some View {
        List(presets, id: \.self) { preset in
            Button {
                model.selectedInstrument = preset
                audio.loadPreset(preset)
            } label: {
                HStack {
                    Text(instrumentName(for: preset))
                    Spacer()
                    Text("#\(preset)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Choose Instrument")
    }

    private func instrumentName(for preset: UInt8) -> String {
        // Basic GM names for first 16 presets as placeholders
        let gm: [String] = [
            "Acoustic Grand Piano","Bright Acoustic Piano","Electric Grand Piano","Honky-tonk Piano",
            "Electric Piano 1","Electric Piano 2","Harpsichord","Clavinet",
            "Celesta","Glockenspiel","Music Box","Vibraphone",
            "Marimba","Xylophone","Tubular Bells","Dulcimer"
        ]
        let idx = Int(preset)
        return idx < gm.count ? gm[idx] : "Program \(idx)"
    }
}

struct JamView: View {
    let key: MusicalKey
    let audio: SamplerAudioEngine

    private let intervals = Scale.majorIntervals
    private let baseOctaves = [5, 4, 3] // high, mid, low

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
