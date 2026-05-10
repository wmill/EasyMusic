import SwiftUI
import AVFoundation
import Combine

// MARK: - Musical Model

enum MusicalKey: String, CaseIterable, Identifiable {
    case C, G, D, A, E, B, FSharp = "F♯", CSharp = "C♯", F, Bb = "B♭", Eb = "E♭", Ab = "A♭", Db = "D♭", Gb = "G♭", Cb = "C♭"
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

struct PlayableNote: Identifiable, Hashable {
    let midiNote: Int
    let noteName: String
    let octave: Int
    let rowIndex: Int
    let degree: Int

    var id: Int {
        midiNote
    }

    var pitchClass: Int {
        ((midiNote % 12) + 12) % 12
    }

    var keyboardOffset: Int {
        (octave - 3) * 12 + pitchClass
    }

    var isBlackKey: Bool {
        [1, 3, 6, 8, 10].contains(pitchClass)
    }
}

struct PianoKey: Identifiable, Hashable {
    let midiNote: Int

    var id: Int {
        midiNote
    }

    var pitchClass: Int {
        ((midiNote % 12) + 12) % 12
    }

    var isBlackKey: Bool {
        [1, 3, 6, 8, 10].contains(pitchClass)
    }
}

struct InstrumentPreset: Codable, Identifiable {
    let program: UInt8
    let name: String
    var id: UInt8 { program }
}

@MainActor
final class InstrumentCatalog: ObservableObject {
    @Published var presets: [InstrumentPreset] = []

    init() {
        loadFromBundle()
    }

    private func loadFromBundle() {
        guard let url = Bundle.main.url(forResource: "instruments", withExtension: "json") else {
            print("instruments.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([InstrumentPreset].self, from: data)
            self.presets = decoded
        } catch {
            print("Failed to load instruments.json: \(error)")
        }
    }
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

// MARK: - Button Styles

struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.3 : 0)
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
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
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .foregroundStyle(.white)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.85), Color.blue, Color(red: 0.1, green: 0.2, blue: 0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color.blue.opacity(0.4), radius: 6, x: 0, y: 4)
                    }
                    .buttonStyle(BounceButtonStyle())
                }
            }
            .padding()
        }
        .navigationTitle("Choose a Key")
    }
}

struct InstrumentSelectionView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var catalog = InstrumentCatalog()
    let audio: SamplerAudioEngine

    var body: some View {
        List(catalog.presets) { preset in
            Button {
                model.selectedInstrument = preset.program
                audio.loadPreset(preset.program)
            } label: {
                HStack {
                    Text(preset.name)
                    Spacer()
                    Text("#\(preset.program)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Choose Instrument")
    }
}

struct JamView: View {
    let key: MusicalKey
    let audio: SamplerAudioEngine

    private let intervals = Scale.majorIntervals
    private let baseOctaves = [5, 4, 3] // high, mid, low
    @State private var activeMIDINotes: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            PianoKeyboardView(
                keys: pianoKeys,
                activeMIDINotes: activeMIDINotes
            )
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 30)

            VStack(spacing: 16) {
                ForEach(groupedNotes, id: \.first?.rowIndex) { rowNotes in
                    HStack(spacing: 16) {
                        ForEach(rowNotes) { note in
                            PressableKey(
                                title: note.noteName,
                                down: {
                                    activeMIDINotes.insert(note.midiNote)
                                    audio.play(midiNote: note.midiNote)
                                },
                                up: {
                                    activeMIDINotes.remove(note.midiNote)
                                    audio.stop(midiNote: note.midiNote)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .navigationTitle(key.rawValue)
        .onDisappear {
            for midiNote in activeMIDINotes {
                audio.stop(midiNote: midiNote)
            }
            activeMIDINotes.removeAll()
        }
    }

    private var playableNotes: [PlayableNote] {
        baseOctaves.enumerated().flatMap { rowIndex, octave in
            intervals.enumerated().map { degree, _ in
                let midi = midiNote(for: key, degree: degree, octave: octave)
                return PlayableNote(
                    midiNote: midi,
                    noteName: noteName(for: key, degree: degree, octave: octave),
                    octave: octave,
                    rowIndex: rowIndex,
                    degree: degree
                )
            }
        }
    }

    private var groupedNotes: [[PlayableNote]] {
        let notesByRow = Dictionary(grouping: playableNotes, by: \.rowIndex)
        return notesByRow.keys.sorted().compactMap { rowIndex in
            notesByRow[rowIndex]?.sorted { $0.degree < $1.degree }
        }
    }

    private var pianoKeys: [PianoKey] {
        let sortedNotes = playableNotes.sorted { $0.midiNote < $1.midiNote }
        guard let firstNote = sortedNotes.first?.midiNote, let lastNote = sortedNotes.last?.midiNote else {
            return []
        }

        return Array(firstNote...lastNote).map { PianoKey(midiNote: $0) }
    }

    private func midiNote(for key: MusicalKey, degree: Int, octave: Int) -> Int {
        let c4 = 60
        let baseCForOctave = c4 + (octave - 4) * 12
        let root = baseCForOctave + key.semitoneOffsetFromC
        return root + intervals[degree]
    }

    private func noteName(for key: MusicalKey, degree: Int, octave: Int) -> String {
        let names = ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"]
        let semitone = (key.semitoneOffsetFromC + intervals[degree]) % 12
        let name = names[semitone]
        return name
    }
}

private func hueFor(title: String) -> Double {
    // Deterministic hue per note label
    let map: [String: Double] = [
        "C": 0.02, "C♯": 0.10, "D": 0.18, "D♯": 0.26, "E": 0.34, "F": 0.42, "F♯": 0.50, "G": 0.58, "G♯": 0.66, "A": 0.74, "A♯": 0.82, "B": 0.90
    ]
    return map[title] ?? 0.3
}

struct PianoKeyboardView: View {
    let keys: [PianoKey]
    let activeMIDINotes: Set<Int>

    var body: some View {
        GeometryReader { geometry in
            let leftInset = keys.first?.isBlackKey == true ? 12.0 : 0.0
            let rightInset = keys.last?.isBlackKey == true ? 12.0 : 0.0
            let whiteKeyCount = max(CGFloat(whiteKeys.count), 1)
            let availableWidth = max(geometry.size.width - leftInset - rightInset, 1)
            let whiteKeyWidth = availableWidth / whiteKeyCount
            let whiteKeyHeight = geometry.size.height
            let blackKeyWidth = whiteKeyWidth * 0.64
            let blackKeyHeight = whiteKeyHeight * 0.62
            let keyboardBlackKeys = blackKeyPlacements(whiteKeyWidth: whiteKeyWidth, blackKeyWidth: blackKeyWidth)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(whiteKeys) { key in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(whiteKeyFill(for: key))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.16), lineWidth: 1)
                            )
                            .frame(width: whiteKeyWidth, height: whiteKeyHeight)
                    }
                }
                .padding(.leading, leftInset)

                ForEach(keyboardBlackKeys, id: \.key.id) { placement in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(blackKeyFill(for: placement.key))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                        )
                        .frame(width: blackKeyWidth, height: blackKeyHeight)
                        .offset(x: leftInset + placement.xOffset, y: 0)
                }
            }
        }
        .frame(height: 92)
        .padding(.horizontal, 6)
        .opacity(0.9)
    }

    private var whiteKeys: [PianoKey] {
        keys.filter { !$0.isBlackKey }
    }

    private func blackKeyPlacements(whiteKeyWidth: CGFloat, blackKeyWidth: CGFloat) -> [(key: PianoKey, xOffset: CGFloat)] {
        var whiteKeysSeen = 0
        var placements: [(key: PianoKey, xOffset: CGFloat)] = []

        for key in keys {
            if key.isBlackKey {
                let xOffset = (CGFloat(whiteKeysSeen) * whiteKeyWidth) - (blackKeyWidth / 2)
                placements.append((key: key, xOffset: xOffset))
            } else {
                whiteKeysSeen += 1
            }
        }

        return placements
    }

    private func whiteKeyFill(for key: PianoKey) -> LinearGradient {
        if activeMIDINotes.contains(key.midiNote) {
            let hue = hueFor(title: noteName(for: key.midiNote))
            return LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.30, brightness: 1.0),
                    Color(hue: hue, saturation: 0.55, brightness: 0.96),
                    Color(hue: hue, saturation: 0.80, brightness: 0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [Color.white, Color(white: 0.95), Color(white: 0.88)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func blackKeyFill(for key: PianoKey) -> LinearGradient {
        if activeMIDINotes.contains(key.midiNote) {
            let hue = hueFor(title: noteName(for: key.midiNote))
            return LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.60, brightness: 0.98),
                    Color(hue: hue, saturation: 0.78, brightness: 0.88),
                    Color(hue: hue, saturation: 0.88, brightness: 0.66)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [Color(white: 0.25), Color(white: 0.12), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func noteName(for midiNote: Int) -> String {
        let names = ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"]
        let pitchClass = ((midiNote % 12) + 12) % 12
        return names[pitchClass]
    }
}

struct PressableKey: View {
    let title: String
    let down: () -> Void
    let up: () -> Void

    @State private var isPressed = false

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, minHeight: 80)
            .foregroundStyle(.white)
            .background(backgroundGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: shadowColor.opacity(isPressed ? 0.2 : 0.45), radius: isPressed ? 2 : 8, x: 0, y: isPressed ? 1 : 5)
            .scaleEffect(isPressed ? 0.93 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
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

    private var backgroundGradient: LinearGradient {
        let hue = hueFor(title: title)
        if isPressed {
            return LinearGradient(
                colors: [Color.orange, Color(hue: 0.08, saturation: 0.8, brightness: 0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.45, brightness: 1.0),
                Color(hue: hue, saturation: 0.6, brightness: 0.9),
                Color(hue: hue, saturation: 0.75, brightness: 0.7)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var shadowColor: Color {
        let hue = hueFor(title: title)
        return Color(hue: hue, saturation: 0.7, brightness: 0.6)
    }

}

#Preview {
    ContentView()
}
