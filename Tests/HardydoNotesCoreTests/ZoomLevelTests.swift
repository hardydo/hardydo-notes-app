import HardydoNotesCore
import Testing

@Suite struct ZoomLevelTests {
    @Test func zoomIsClampedBetweenSixtyAndThreeHundredPercent() {
        #expect(ZoomLevel.normalized(0.1) == 0.6, "zoom stops at 60%")
        #expect(ZoomLevel.normalized(9) == 3, "zoom stops at 300%")
    }

    @Test func zoomRoundsToTheNearestFivePercent() {
        #expect(ZoomLevel.normalized(1.024) == 1, "zoom rounds down to the nearest 5%")
        #expect(ZoomLevel.normalized(1.026) == 1.05, "zoom rounds up to the nearest 5%")
    }

    @Test func normalisingTwiceChangesNothing() {
        #expect(ZoomLevel.normalized(ZoomLevel.normalized(1.337)) == ZoomLevel.normalized(1.337), "normalising twice changes nothing")
    }
}
