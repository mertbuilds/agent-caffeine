import AppKit

/// The system sounds through `NSSound`: on the output device in use, at
/// the volume of the system, and silent while the Mac is muted.
@MainActor
final class SystemLidChimePlayer: LidChimePlaying {
    func play(_ sound: LidChimeSound) -> Bool {
        guard let system = NSSound(named: sound.rawValue) else { return false }
        // The sound of a name is one object, and one that still plays
        // refuses to start again.
        system.stop()
        return system.play()
    }
}
