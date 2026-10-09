import HardydoNotesCore
import Observation
import SwiftUI

/// How the window is laid out: text size, the editor's share of split view, scroll sync and the sidebar.
@MainActor
@Observable
final class LayoutSettings {
    private(set) var zoom: CGFloat = 1
    private(set) var splitRatio = 0.5
    private(set) var isScrollSynced = true
    var sidebarVisibility = NavigationSplitViewVisibility.all
    /// The unrounded zoom a pinch or ⌘-scroll accumulates, so many tiny steps still add up to the next 5%.
    @ObservationIgnored private var zoomTarget: CGFloat = 1
    @ObservationIgnored private var zoomSave: Task<Void, Never>?
    @ObservationIgnored private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        if let saved = preferences.zoom {
            zoom = CGFloat(ZoomLevel.normalized(saved))
            zoomTarget = zoom
        }
        if let saved = preferences.splitRatio { splitRatio = Self.clampedSplit(saved) }
        if let saved = preferences.isScrollSynced { isScrollSynced = saved }
    }

    // A pinch sends many small steps, so the level is written once they stop.
    func setZoom(_ value: CGFloat) {
        zoomTarget = CGFloat(min(max(Double(value), ZoomLevel.range.lowerBound), ZoomLevel.range.upperBound))
        let level = CGFloat(ZoomLevel.normalized(Double(zoomTarget)))
        guard level != zoom else { return }
        zoom = level
        zoomSave?.cancel()
        zoomSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveZoom()
        }
    }

    func zoom(by factor: CGFloat) {
        setZoom(zoomTarget * factor)
    }

    func dragSplit(to ratio: Double) {
        splitRatio = Self.clampedSplit(ratio)
    }

    func endSplitDrag() {
        preferences.splitRatio = splitRatio
    }

    func toggleScrollSync() {
        isScrollSynced.toggle()
        preferences.isScrollSynced = isScrollSynced
    }

    /// Writes a zoom change that was still waiting, for quitting.
    func flush() {
        if zoomSave != nil { saveZoom() }
    }

    private func saveZoom() {
        zoomSave?.cancel()
        zoomSave = nil
        preferences.zoom = Double(zoom)
    }

    private static func clampedSplit(_ ratio: Double) -> Double {
        min(max(ratio, 0.15), 0.85)
    }
}
