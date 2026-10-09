import Foundation

/// Editor and preview zoom, kept to 5% steps so a run of tiny pinch or scroll changes restyles the text only once per step.
public enum ZoomLevel {
    public static let range: ClosedRange<Double> = 0.6...3

    public static func normalized(_ value: Double) -> Double {
        (min(max(value, range.lowerBound), range.upperBound) * 20).rounded() / 20
    }
}
