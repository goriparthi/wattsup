import CoreGraphics

/// Whether a status item frame can actually be seen, given the screen and its notch areas.
/// The auxiliary areas are the menu bar strips either side of the camera housing.
public enum MenuBarGeometry {
    public static func isVisible(item: CGRect, screen: CGRect, leftOfNotch: CGRect?, rightOfNotch: CGRect?) -> Bool {
        guard item.width > 1, screen.intersects(item) else { return false }
        guard let left = leftOfNotch, let right = rightOfNotch, right.minX > left.maxX else { return true }
        // Anything overlapping the gap between the two strips sits under the camera housing
        let notch = CGRect(x: left.maxX, y: min(left.minY, right.minY),
                           width: right.minX - left.maxX, height: max(left.height, right.height))
        return !notch.intersects(item.insetBy(dx: 1, dy: 0))
    }
}
