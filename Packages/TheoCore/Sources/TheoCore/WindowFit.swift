#if canImport(CoreGraphics)
import CoreGraphics // CGRect's members (Foundation has them on Linux)
#endif
import Foundation

/// Where a Mac window belongs on its screen. `visible` is the part of the screen windows may use
/// (below the menu bar, above the Dock). Both rectangles are in screen coordinates, which grow
/// upwards: `maxY` is a window's top edge, `minY` its bottom edge.
public enum WindowFit {
    /// `frame` moved, and shrunk where it's bigger than `visible`, so that all of it lies inside
    /// `visible`. A window taller than the screen gets the screen's height, from just under the
    /// menu bar to just above the Dock. A frame already inside comes back unchanged.
    public static func fitted(_ frame: CGRect, in visible: CGRect) -> CGRect {
        guard visible.width > 0, visible.height > 0, frame.width > 0, frame.height > 0 else { return frame }
        var fitted = frame
        if fitted.width > visible.width {
            fitted.size.width = visible.width
        }
        if fitted.height > visible.height {
            fitted.origin.y = frame.maxY - visible.height
            fitted.size.height = visible.height
        }
        if fitted.maxX > visible.maxX { fitted.origin.x = visible.maxX - fitted.width }
        if fitted.minX < visible.minX { fitted.origin.x = visible.minX }
        if fitted.maxY > visible.maxY { fitted.origin.y = visible.maxY - fitted.height }
        if fitted.minY < visible.minY { fitted.origin.y = visible.minY }
        return fitted
    }

    /// Whether `frame` already lies inside `visible`, to within a point.
    public static func fits(_ frame: CGRect, in visible: CGRect) -> Bool {
        let fitted = fitted(frame, in: visible)
        return abs(fitted.minX - frame.minX) < 1 && abs(fitted.minY - frame.minY) < 1
            && abs(fitted.width - frame.width) < 1 && abs(fitted.height - frame.height) < 1
    }
}
