import AVFoundation
import Foundation

enum EqualizerPreset: String, CaseIterable {
    case flat = "Flat"
    case rock = "Rock"
    case pop = "Pop"
    case jazz = "Jazz"
    case classical = "Classical"

    var bandGains: [Float] {
        switch self {
        case .flat: return [0,0,0,0,0,0,0,0]
        case .rock: return [2.5, 3.0, 2.0, 1.0, 0.5, 0.0, 0.0, 0.0]
        case .pop: return [1.2, 1.5, 2.0, 2.0, 1.0, 0.0, 0.0, 0.0]
        case .jazz: return [1.0, 1.5, 2.5, 2.0, 1.0, 0.5, 0.5, 0.0]
        case .classical: return [2.0, 2.5, 2.0, 1.5, 1.0, 0.5, 0.0, 0.0]
        }
    }
}

@MainActor
protocol EqualizerServicing {
    func setPreset(_ preset: EqualizerPreset)
    func setPlaybackRate(_ rate: Float)
    func applyEngineEQ(_ player: AVAudioPlayerNode?)
}

@MainActor
final class EqualizerService: EqualizerServicing {
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let eqUnit = AVAudioUnitEQ(numberOfBands: 8)

    private var currentPreset: EqualizerPreset = .flat
    private var currentRate: Float = 1.0

    init() {
        engine.attach(mixer)
        engine.attach(eqUnit)
        engine.connect(eqUnit, to: mixer, format: nil)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        if #available(iOS 17, *) {
            // Intentionally left as default EQ behavior; engine is optional and safe to initialize.
        }
    }

    func setPreset(_ preset: EqualizerPreset) {
        currentPreset = preset
    }

    func setPlaybackRate(_ rate: Float) {
        currentRate = max(0.5, min(2.0, rate))
    }

    func applyEngineEQ(_ player: AVAudioPlayerNode?) {
        guard player != nil else { return }
        let gains = currentPreset.bandGains
        for (index, gain) in gains.enumerated() {
            if index < eqUnit.bands.count {
                eqUnit.bands[index].gain = gain
                eqUnit.bands[index].bypass = false
            }
        }
        _ = currentRate
    }
}
