// AppKit regression checks; run scripts/test-picker.sh in a macOS GUI session.
import AppKit
import SelbyCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var failures = 0
var passes = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        passes += 1
        print("ok    \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

@MainActor
func withPicker(_ body: (PickerPanel, PickerModel, () -> [PickerOutcome]) -> Void) {
    let browser = Browser(bundleID: "test", name: "Test", url: URL(fileURLWithPath: "/Test.app"))
    let model = PickerModel(urls: [URL(string: "https://example.com")!], browsers: [browser], defaultIndex: 0)
    var outcomes: [PickerOutcome] = []
    model.onFinish = { outcomes.append($0) }
    let panel = PickerPanel(model: model, maxListHeight: 300)
    panel.monitorOutsideClicks()
    defer {
        panel.stopMonitoringClicks()
        panel.close()
    }
    body(panel, model, { outcomes })
}

func mouseDown(timestamp: TimeInterval, windowNumber: Int = 0) -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: timestamp,
        windowNumber: windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
    )!
}

MainActor.assumeIsolated {
    withPicker { panel, model, outcomes in
        panel.resignKey()
        check(outcomes().isEmpty, "focus loss does not discard the first URL")
        model.choose(0)
        check(outcomes() == [.chose(model.browsers[0])], "link remains selectable after focus loss")
    }
    withPicker { panel, model, outcomes in
        panel.handleMouseDown(mouseDown(timestamp: 0), local: false)
        check(outcomes().isEmpty, "delayed initiating click cannot cancel a new picker")
        model.choose(0)
        check(outcomes() == [.chose(model.browsers[0])], "link survives delayed initiating click")
    }
    withPicker { panel, _, outcomes in
        panel.handleMouseDown(mouseDown(timestamp: ProcessInfo.processInfo.systemUptime + 1), local: false)
        check(outcomes() == [.cancelled(.outsideClick)], "subsequent external click still dismisses")
    }
    withPicker { panel, _, outcomes in
        let event = mouseDown(timestamp: ProcessInfo.processInfo.systemUptime + 1, windowNumber: panel.windowNumber)
        check(event.window === panel, "test event targets the picker")
        panel.handleMouseDown(event, local: true)
        check(outcomes().isEmpty, "click inside picker does not cancel browser selection")
    }
    withPicker { panel, _, outcomes in
        panel.handleMouseDown(mouseDown(timestamp: ProcessInfo.processInfo.systemUptime + 1), local: true)
        check(outcomes() == [.cancelled(.outsideClick)], "click elsewhere in Selby dismisses")
    }
    withPicker { panel, _, outcomes in
        panel.cancelOperation(nil)
        panel.resignKey()
        check(outcomes() == [.cancelled(.dismissed)], "Escape dismisses exactly once")
    }
}
print("\n\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
