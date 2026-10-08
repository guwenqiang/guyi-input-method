import Foundation
import CoreGraphics

/// Some hosts disagree by one line between modern and legacy IMK geometry.
/// Calibrate only when both APIs describe the same cursor and line height.
public struct CaretGeometry {
    private var verticalOffset: CGFloat = 0
    private var lineHeight: CGFloat = 0
    public init() {}
    public mutating func calibrate(primary: CGRect, legacy: CGRect) {
        guard CandidatePlacement.validCaret(primary), CandidatePlacement.validCaret(legacy),
              abs(primary.minX - legacy.minX) < 2,
              abs(primary.height - legacy.height) < 1,
              abs(primary.minY - legacy.minY) <= primary.height * 1.1 else { return }
        verticalOffset = legacy.minY - primary.minY
        lineHeight = primary.height
    }
    public func adjusted(_ rect: CGRect) -> CGRect {
        guard lineHeight > 0, abs(rect.height - lineHeight) <= 2 else { return rect }
        // Empty Qt editors report an 18pt line, then 19pt after the first
        // character. A whole-line origin discrepancy must follow that height.
        if abs(abs(verticalOffset) - lineHeight) < 1 {
            return rect.offsetBy(dx: 0, dy: verticalOffset < 0 ? -rect.height : rect.height)
        }
        return rect.offsetBy(dx: 0, dy: verticalOffset)
    }
}
