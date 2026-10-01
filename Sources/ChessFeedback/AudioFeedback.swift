import AVFAudio
import ChessContent
import Foundation

/// Plays the effects of a `SoundPack` through one `AVAudioEngine` and a pool of player nodes.
///
/// Every effect is rendered once when the pack loads. When the engine cannot start, such as
/// without an output device, playing is silent. The engine restarts after an interruption or a
/// configuration change. The owner sets `isEnabled` and `volume` from the settings.
@preconcurrency
@MainActor
public final class AudioFeedback {
  public var isEnabled: Bool
  /// 0...1, applied to the engine's main mixer.
  var volume: Float {
    didSet { engine.mainMixerNode.outputVolume = volume }
  }
  /// Whether the engine runs; false means playing is silent.
  public private(set) var isRunning = false

  private let engine = AVAudioEngine()
  private var format: AVAudioFormat?
  private var players: [AVAudioPlayerNode] = []
  private var buffers: [SoundEffectID: AVAudioPCMBuffer] = [:]
  private var nextPlayer = 0
  private let observers = NotificationObservers()

  public init(pack: SoundPack, isEnabled: Bool = true, volume: Float = 1) {
    self.isEnabled = isEnabled
    self.volume = volume
    engine.mainMixerNode.outputVolume = volume
    #if os(iOS) || os(tvOS)
      // Ambient: the user's music keeps playing, and the silent switch mutes the effects.
      try? AVAudioSession.sharedInstance().setCategory(.ambient)
      observers.add(AVAudioSession.interruptionNotification) { [weak self] note in
        let ended =
          (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
          .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
        Task { @MainActor in
          if ended { self?.startEngine() } else { self?.isRunning = false }
        }
      }
    #endif
    observers.add(.AVAudioEngineConfigurationChange, object: engine) { [weak self] _ in
      Task { @MainActor in self?.startEngine() }
    }
    load(pack)
  }

  /// Renders every effect of `pack` and sizes the player pool to its voice count.
  public func load(_ pack: SoundPack) {
    engine.stop()
    isRunning = false
    for player in players { engine.detach(player) }
    players = []
    buffers = [:]
    nextPlayer = 0
    guard let format = AVAudioFormat(standardFormatWithSampleRate: pack.sampleRate, channels: 1)
    else {
      self.format = nil
      return
    }
    self.format = format
    for effect in SoundEffectID.allCases {
      buffers[effect] = Self.buffer(
        SoundPackRenderer.samples(for: effect, in: pack),
        format: format
      )
    }
    for _ in 0..<max(1, pack.voiceCount) {
      let player = AVAudioPlayerNode()
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: format)
      players.append(player)
    }
    startEngine()
  }

  public func play(_ effect: SoundEffectID) {
    guard isEnabled, let buffer = buffers[effect], !players.isEmpty else { return }
    if !engine.isRunning { startEngine() }
    guard isRunning else { return }
    let player = players[nextPlayer]
    nextPlayer = (nextPlayer + 1) % players.count
    player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    player.play()
  }

  private func startEngine() {
    guard format != nil else { return }
    do {
      #if os(iOS) || os(tvOS)
        try AVAudioSession.sharedInstance().setActive(true)
      #endif
      try engine.start()
      isRunning = true
    } catch {
      isRunning = false
    }
  }

  private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard !samples.isEmpty,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
      ),
      let channel = buffer.floatChannelData?[0]
    else { return nil }
    samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    return buffer
  }
}

/// Notification observers that are removed when the owner goes away.
final class NotificationObservers {
  private var tokens: [any NSObjectProtocol] = []

  func add(
    _ name: Notification.Name,
    object: AnyObject? = nil,
    _ handler: @escaping @Sendable (Notification) -> Void
  ) {
    tokens.append(
      NotificationCenter.default.addObserver(
        forName: name,
        object: object,
        queue: .main,
        using: handler
      )
    )
  }

  deinit {
    for token in tokens { NotificationCenter.default.removeObserver(token) }
  }
}
