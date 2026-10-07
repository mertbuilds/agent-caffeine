import Carbon

/// A keyboard layout of macOS, read through `UCKeyTranslate`. It reads the
/// layout and no key press, so it needs no permission.
struct SystemKeyLayout: KeyLayout {
    /// macOS posts this when the user selects another keyboard layout.
    static let changed = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)

    /// The 'uchr' data of the layout.
    private let data: Data
    private let keyboardType: UInt32

    /// The layout in use, then the one macOS itself falls back on for the
    /// shortcuts of a layout without Latin letters. An input source
    /// without layout data, as some input methods are, is left out.
    static func inUse() -> [KeyLayout] {
        [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()]
            .compactMap { $0?.takeRetainedValue() }
            .compactMap(SystemKeyLayout.init)
    }

    init?(_ source: TISInputSource) {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        guard !data.isEmpty else { return nil }
        self.data = data
        keyboardType = UInt32(LMGetKbdType())
    }

    func characters(keyCode: UInt16) -> String? {
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeys, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
