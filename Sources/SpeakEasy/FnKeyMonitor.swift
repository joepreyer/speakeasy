import AppKit

/// Watches the fn (globe) key system-wide via a listen-only CGEventTap.
/// Requires the Input Monitoring permission.
final class FnKeyMonitor {
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?
    var onOtherKeyWhileFnHeld: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsDown = false

    var isRunning: Bool { tap != nil }

    /// Returns false if the event tap could not be created (Input Monitoring not granted).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let down = event.flags.contains(.maskSecondaryFn)
            guard down != fnIsDown else { return }
            fnIsDown = down
            let handler = down ? onFnDown : onFnUp
            DispatchQueue.main.async { handler?() }
        case .keyDown:
            // fn is being used as a modifier (fn+delete, fn+arrows, ...), not push-to-talk.
            if fnIsDown {
                DispatchQueue.main.async { self.onOtherKeyWhileFnHeld?() }
            }
        default:
            break
        }
    }
}
