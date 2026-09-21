import AppKit
import SelbyCore
import SwiftUI
import os

/// A Spotlight-style floating panel: borderless, non-activating, able to take
/// keyboard focus while the previously frontmost app stays active. Dismisses
/// on Escape, on an actual outside click, or via `PickerModel` callbacks.
final class PickerPanel: NSPanel {
    private let model: PickerModel
    private let log = Logger(subsystem: "dev.selby.Selby", category: "picker")
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var presentedAt: TimeInterval = 0

    init(model: PickerModel, maxListHeight: CGFloat) {
        self.model = model
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // Focus changes alone must not hide or discard an unopened link.
        hidesOnDeactivate = false
        // Show over full-screen apps and on whichever Space the click happened.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // We order the panel out manually; auto-release on close would leave a
        // dangling reference and crash on the second dismissal path.
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        let host = NSHostingController(
            rootView: BrowserPickerView(model: model, maxListHeight: maxListHeight)
        )
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host
    }

    // Borderless windows refuse key status unless this is overridden; the
    // picker is keyboard-driven, so it must become key.
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !model.handleKey(event) {
            super.keyDown(with: event)
        }
    }

    // Escape arrives here (via the responder chain) as well as through
    // keyDown; PickerModel's `finished` guard makes the double call harmless.
    override func cancelOperation(_ sender: Any?) {
        model.cancel(.dismissed)
    }

    override func resignKey() {
        super.resignKey()
        log.notice("Picker lost keyboard focus; retaining pending links")
    }

    /// Event timestamps and systemUptime use the same monotonic clock. A
    /// delayed copy of the click that opened us must not also dismiss us.
    func monitorOutsideClicks() {
        stopMonitoringClicks()
        presentedAt = ProcessInfo.processInfo.systemUptime
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            // AppKit invokes both event monitors on the main thread. Handle
            // synchronously so cancellation cannot run after another URL arrives.
            MainActor.assumeIsolated { self?.handleMouseDown(event, local: false) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseDown(event, local: true) }
            return event
        }
    }

    func handleMouseDown(_ event: NSEvent, local: Bool) {
        guard event.timestamp > presentedAt else { return }
        guard !local || event.window !== self else { return }
        model.cancel(.outsideClick)
    }

    func stopMonitoringClicks() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }
}
