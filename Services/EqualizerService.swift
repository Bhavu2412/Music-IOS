import Foundation

/// 10-band EQ presets (gains in dB) for the bands in `EqualizerPreset.frequencies`.
enum EqualizerPreset: String, CaseIterable, Identifiable {
    case flat = "Flat"
    case bassBoost = "Bass Boost"
    case trebleBoost = "Treble Boost"
    case vocal = "Vocal"
    case rock = "Rock"
    case pop = "Pop"
    case jazz = "Jazz"
    case classical = "Classical"
    case electronic = "Electronic"
    case acoustic = "Acoustic"
    case lateNight = "Late Night"

    var id: Self { self }

    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    var bandGains: [Float] {
        switch self {
        case .flat:        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost:   [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .trebleBoost: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .vocal:       [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]
        case .rock:        [4, 3, 2, 0, -1, -1, 1, 2, 3, 4]
        case .pop:         [-1, 0, 2, 3, 4, 3, 1, 0, -1, -1]
        case .jazz:        [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]
        case .classical:   [4, 3, 2, 1, 0, 0, 0, 1, 2, 3]
        case .electronic:  [5, 4, 1, 0, -2, 1, 0, 1, 4, 5]
        case .acoustic:    [3, 3, 2, 1, 1, 1, 2, 2, 2, 1]
        case .lateNight:   [4, 3, 1, 0, 0, 0, 0, 1, 2, 3] // loudness curve for low volume
        }
    }
}
