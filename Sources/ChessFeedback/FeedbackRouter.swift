import ChessContent
import ChessPlay
import Foundation

/// Where the router sends sounds; `AudioFeedback` in the app, a recorder in tests.
@MainActor
protocol SoundOutput {
    func play(_ effect: SoundEffectID)
}

/// Where the router sends haptics; `HapticFeedback` in the app, a recorder in tests.
@MainActor
protocol HapticOutput {
    func play(_ haptic: HapticEventID)
}

extension AudioFeedback: SoundOutput {}
extension HapticFeedback: HapticOutput {}

/// Plays the sound and haptic of each session event, as `FeedbackTuning` maps them.
public struct FeedbackRouter: FeedbackSink {
    private let sound: any SoundOutput
    private let haptics: any HapticOutput
    private let tuning: FeedbackTuning

    public init(audio: AudioFeedback, haptics: HapticFeedback, tuning: FeedbackTuning) {
        self.init(sound: audio, haptics: haptics, tuning: tuning)
    }

    init(sound: any SoundOutput, haptics: any HapticOutput, tuning: FeedbackTuning) {
        self.sound = sound
        self.haptics = haptics
        self.tuning = tuning
    }

    public func receive(_ event: FeedbackEvent) {
        let cue = Self.cue(for: event, in: tuning)
        if let effect = cue.sound { sound.play(effect) }
        if let haptic = cue.haptic { haptics.play(haptic) }
    }

    /// The sound and haptic of `event`: a move plays its own sound, everything else is data.
    static func cue(for event: FeedbackEvent, in tuning: FeedbackTuning) -> (sound: SoundEffectID?, haptic: HapticEventID?) {
        let kind: FeedbackEventKind
        switch event {
        case .moved(let effect): return (effect, tuning.moveHaptics[effect])
        case .gameStarted: kind = .gameStarted
        case .illegalMove: kind = .illegalMove
        case .gameOver: kind = .gameOver
        case .lowTime: kind = .lowTime
        case .puzzleCorrect: kind = .puzzleCorrect
        case .puzzleWrong: kind = .puzzleWrong
        }
        let cue = tuning.events[kind]
        return (cue?.sound, cue?.haptic)
    }
}
