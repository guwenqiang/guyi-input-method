import Foundation
import CoreGraphics

public enum CandidatePlacement {
    public static func validCaret(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite &&
        rect.height >= 4 && rect.height <= 300 && rect.width >= 0 && rect.width <= 20_000
    }
    public static func frame(caret: CGRect, desired: CGSize, visible: CGRect, preferredAbove: Bool? = nil, avoiding: CGRect? = nil, keepSide: Bool = false) -> CGRect? {
        guard validCaret(caret), visible.intersects(caret.insetBy(dx: -0.5, dy: 0)),
              desired.width > 0, desired.height > 0 else { return nil }
        let bounds = visible.insetBy(dx: 8, dy: 8)
        let gap: CGFloat = 8
        let obstacle = avoiding.map { caret.union($0) } ?? caret
        let above = max(0, bounds.maxY - obstacle.maxY - gap)
        let belowGap = gap
        let below = max(0, obstacle.minY - belowGap - bounds.minY)
        let useAbove: Bool
        let fitsAbove = above >= desired.height
        let fitsBelow = below >= desired.height
        if keepSide, let preferredAbove, (preferredAbove ? above : below) >= 80 { useAbove = preferredAbove }
        else if fitsAbove && fitsBelow { useAbove = preferredAbove ?? true }
        else if fitsAbove { useAbove = true }
        else if fitsBelow { useAbove = false }
        else { useAbove = above >= below }
        let available = useAbove ? above : below
        guard available >= 44, bounds.width > 0 else { return nil }
        let height = min(desired.height, available)
        let width = min(desired.width, bounds.width)
        let left = min(max(caret.minX, bounds.minX), bounds.maxX - width)
        let bottom = useAbove ? obstacle.maxY + gap : obstacle.minY - belowGap - height
        return CGRect(x: left, y: bottom, width: width, height: height)
    }
}
