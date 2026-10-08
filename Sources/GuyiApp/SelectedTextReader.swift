import AppKit
import GuyiCore

/// Reads the selection. If its bounds are unavailable, a bounded scan compares
/// visible static labels locally with that exact selection to locate its box.
/// Only the selected text is returned to the translation caller.
final class SelectedTextReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.guyi.selection-reader", qos: .userInitiated)
    private var cachedDocument: (pid_t, AXUIElement, String, AXUIElement)?
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func parameter(_ element: AXUIElement, _ name: String, _ argument: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, argument, &value) == .success else { return nil }
        return value
    }
    @MainActor func readAsync(pid: pid_t, selectionPointer: NSPoint? = nil,
                              requirePointerMatch: Bool = false) async -> (String, NSRect)? {
        let pointer = selectionPointer ?? NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map(\.frame)
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.read(pid: pid, pointer: pointer, top: top,
                                                                     screens: screens, requirePointerMatch: requirePointerMatch)) }
        }
    }
    private func read(pid: pid_t, pointer: NSPoint, top: CGFloat, screens: [CGRect],
                      requirePointerMatch: Bool) -> (String, NSRect)? {
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        guard !SensitiveContentPolicy.protectedApplication(bundle) else { return nil }
        let terminal = ["com.googlecode.iterm2", "com.apple.Terminal"].contains(bundle ?? "")
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        var candidates: [AXUIElement] = []
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(app, Float(pointer.x), Float(top - pointer.y), &hit)
        if let hit { candidates.append(hit) }
        if let focused = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = focused as! AXUIElement
            if attribute(element, kAXSubroleAttribute) as? String == "AXSecureTextField" { return nil }
            candidates.append(element)
        }
        var locatedSelection = false
        func extract(_ current: AXUIElement) -> (String, NSRect)? {
            locatedSelection = false
            if attribute(current, kAXSubroleAttribute) as? String == "AXSecureTextField" { return nil }
            let marker = attribute(current, "AXSelectedTextMarkerRange")
            var text = attribute(current, kAXSelectedTextAttribute) as? String
            if text?.isEmpty != false, let marker { text = parameter(current, "AXStringForTextMarkerRange", marker) as? String }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= 4_000, !SelectionTranslationPolicy.isNonlinguisticSelection(text) else { return nil }
            var bounds = NSRect(x: pointer.x, y: pointer.y - 9, width: 1, height: 18)
            // Chromium exposes exact webpage selections through opaque markers.
            // Use their bounds before a possibly stale numeric text range.
            var value: CFTypeRef?
            if !terminal {
                value = marker.flatMap { parameter(current, "AXBoundsForTextMarkerRange", $0) }
                if value == nil, let range = attribute(current, kAXSelectedTextRangeAttribute) {
                    value = parameter(current, kAXBoundsForRangeParameterizedAttribute, range)
                }
            }
            if !terminal, let value, CFGetTypeID(value) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0,
                   rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height < 1000 {
                    let reported = NSRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
                    guard screens.contains(where: { $0.intersects(reported) }) else { return nil }
                    bounds = reported
                    locatedSelection = true
                }
            }
            if !terminal, !locatedSelection, attribute(current, kAXRoleAttribute) as? String == "AXStaticText",
               attribute(current, kAXValueAttribute) as? String == text,
               let position = attribute(current, kAXPositionAttribute), let size = attribute(current, kAXSizeAttribute),
               CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                var point = CGPoint.zero, dimensions = CGSize.zero
                if AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
                   dimensions.width > 0, dimensions.height > 0, dimensions.height < 1000 {
                    let box = CGRect(x: point.x, y: top - point.y - dimensions.height, width: dimensions.width, height: dimensions.height)
                    if screens.contains(where: { $0.intersects(box) }) { bounds = box; locatedSelection = true }
                }
            }
            if requirePointerMatch {
                if locatedSelection {
                    guard bounds.insetBy(dx: -24, dy: -24).contains(pointer) else { return nil }
                } else {
                    guard let position = attribute(current, kAXPositionAttribute),
                          let size = attribute(current, kAXSizeAttribute),
                          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
                    var point = CGPoint.zero, dimensions = CGSize.zero
                    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
                          AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
                          NSRect(x: point.x, y: top - point.y - dimensions.height,
                                 width: dimensions.width, height: dimensions.height)
                            .insetBy(dx: -24, dy: -24).contains(pointer) else { return nil }
                }
            }
            return (text, bounds)
        }
        var fallbackSelection: (String, NSRect)?
        for start in candidates {
            var element: AXUIElement? = start
            for _ in 0..<8 {
                guard let current = element else { break }
                if let selected = extract(current) { if locatedSelection { return selected }; if fallbackSelection == nil { fallbackSelection = selected } }
                guard let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                element = (parent as! AXUIElement)
            }
        }
        // Rich chat messages may keep focus on the composer while a separate
        // native text node owns the selection. Search the focused window.
        guard let window = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let windowElement = window as! AXUIElement
        let windowTitle = attribute(windowElement, kAXTitleAttribute) as? String ?? ""
        if let cachedDocument, cachedDocument.0 == pid, CFEqual(cachedDocument.1, windowElement),
           cachedDocument.2 == windowTitle, let selected = extract(cachedDocument.3), locatedSelection { return selected }
        cachedDocument = nil
        var stack: [(AXUIElement, Int)] = [(window as! AXUIElement, 0)], visited = 0
        let deadline = Date().addingTimeInterval(0.18)
        while let (current, depth) = stack.popLast(), visited < 360, Date() < deadline {
            visited += 1
            let role = attribute(current, kAXRoleAttribute) as? String ?? ""
            if ["AXWebArea", "AXStaticText", "AXTextArea", "AXTextField", "AXRow", "AXGroup"].contains(role),
               let selected = extract(current) {
                if locatedSelection {
                    cachedDocument = (pid, windowElement, windowTitle, current)
                    return selected
                }
                if fallbackSelection == nil { fallbackSelection = selected }
            }
            if depth < 18 {
                let children = (attribute(current, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(80)
                stack += children.reversed().map { ($0, depth + 1) }
            }
        }
        return fallbackSelection
    }
}
