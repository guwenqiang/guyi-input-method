import Foundation

/// Coalesces wheel input and advances by at most one third of the selected area
/// between captures, retaining overlap even during fast mouse/trackpad gestures.
public struct ScrollStepQueue {
    public private(set) var pending: Double = 0
    public init() {}
    public mutating func add(_ delta: Double) {
        guard delta.isFinite else { return }
        pending = min(100_000, max(-100_000, pending + delta))
    }
    public mutating func take(viewportHeight: Double) -> Int32? {
        guard abs(pending) >= 0.5 else { pending = 0; return nil }
        let limit = max(1, min(120, floor(viewportHeight / 3)))
        let step = min(limit, max(-limit, pending)).rounded()
        pending -= step
        return Int32(step)
    }
    public mutating func clear() { pending = 0 }
}
