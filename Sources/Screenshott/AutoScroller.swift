import AppKit
import ApplicationServices
import ScreenshottCore

/// Accessibility permission, which auto-scroll needs: posting input to other apps is
/// "controlling the computer". Without it macOS drops our scroll events silently.
/// Unlike Screen Recording, a grant takes effect without relaunching.
@MainActor
enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt if we are not trusted — macOS only does that once per
    /// app; after that the user has to go to System Settings.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 won't read from a global var.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

/// Scrolls whatever is under the capture region.
@MainActor
protocol ScrollDriver: AnyObject {
    /// `points` positive scrolls further down the document. `inverted` flips the wheel
    /// for apps that read it the other way round.
    func scroll(points: Double, inverted: Bool) async
}

/// Posts pixel scroll-wheel events, like a trackpad, at a point on screen.
@MainActor
final class WheelScroller: ScrollDriver {
    /// Where the events go, in global CoreGraphics points (top-left origin).
    let location: CGPoint
    /// Points per event. A long scroll goes as a quick run of events, the way a swipe
    /// arrives, rather than one huge jump some apps cut short.
    private static let chunk = 80.0

    init(location: CGPoint) {
        self.location = location
    }

    func scroll(points: Double, inverted: Bool) async {
        // The pointer has to be over the region: scroll events go to the window under it.
        let pointer = CGEvent(source: nil)?.location ?? location
        if abs(pointer.x - location.x) > 1 || abs(pointer.y - location.y) > 1 {
            CGWarpMouseCursorPosition(location)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        // A positive wheel value scrolls up.
        let sign: Double = inverted ? 1 : -1
        var remaining = points.rounded()
        while remaining != 0 {
            let step = remaining > 0 ? min(remaining, Self.chunk) : max(remaining, -Self.chunk)
            if let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                wheel1: Int32(sign * step), wheel2: 0, wheel3: 0
            ) {
                event.location = location
                event.post(tap: .cghidEventTap)
            }
            remaining -= step
            if remaining != 0 { try? await Task.sleep(for: .milliseconds(8)) }
        }
    }
}

/// Another app's on-screen window, for the hover highlight and click-to-pick.
struct ScrollTarget {
    /// Global CoreGraphics points (top-left origin).
    let bounds: CGRect
    let pid: pid_t
}

@MainActor
enum ScrollTargets {
    /// On-screen app windows, front to back. Taken before our overlay goes up.
    static func windows() -> [ScrollTarget] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 20, rect.height >= 20
            else { return nil }
            return ScrollTarget(bounds: rect, pid: pid)
        }
    }

    /// The scroll area under `point` (global CoreGraphics points) in app `pid`, through
    /// Accessibility — the part of a window that actually scrolls, without its toolbar
    /// and sidebar. Nil without permission or when the app exposes none there.
    static func scrollArea(at point: CGPoint, pid: pid_t) -> CGRect? {
        guard Accessibility.isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        // A hung app must not hang the overlay.
        AXUIElementSetMessagingTimeout(app, 0.3)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit
        else { return nil }
        for _ in 0..<40 {
            if string(element, kAXRoleAttribute) == kAXScrollAreaRole as String, let frame = frame(of: element),
               frame.width >= 40, frame.height >= 40 {
                return frame
            }
            guard let parent = value(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                return nil
            }
            element = parent as! AXUIElement
        }
        return nil
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
