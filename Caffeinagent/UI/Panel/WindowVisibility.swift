import AppKit
import SwiftUI

/// Tells whether the window it sits in is on screen. The window of the
/// menu stays alive while the menu is closed.
struct WindowVisibility: NSViewRepresentable {
    @Binding var isVisible: Bool
    var holder: Holder?

    /// Knows the window, so the menu can close itself.
    final class Holder {
        fileprivate(set) weak var window: NSWindow?

        /// As a click outside the menu: the window goes and stays alive.
        func close() {
            window?.orderOut(nil)
        }
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.holder = holder
        view.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        var onChange: ((Bool) -> Void)?
        var holder: Holder?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            holder?.window = window
            guard let window else {
                report(false)
                return
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.report(self?.window?.occlusionState.contains(.visible) ?? false)
            }
            report(window.occlusionState.contains(.visible))
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        private func report(_ visible: Bool) {
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }
    }
}
