import HardydoNotesCore

func runZoomLevelChecks() {
    checkEqual(ZoomLevel.normalized(0.1), 0.6, "zoom stops at 60%")
    checkEqual(ZoomLevel.normalized(9), 3, "zoom stops at 300%")
    checkEqual(ZoomLevel.normalized(1.024), 1, "zoom rounds down to the nearest 5%")
    checkEqual(ZoomLevel.normalized(1.026), 1.05, "zoom rounds up to the nearest 5%")
    checkEqual(ZoomLevel.normalized(ZoomLevel.normalized(1.337)), ZoomLevel.normalized(1.337), "normalising twice changes nothing")
}
