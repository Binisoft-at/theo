import CoreGraphics
import Foundation
import Testing
@testable import TheoCore

@Suite("Mac window stays on its screen")
struct WindowFitTests {
    /// A 1512 × 982 laptop screen: menu bar 37 points, Dock 72 points.
    let visible = CGRect(x: 0, y: 72, width: 1512, height: 873)

    @Test func aWindowInsideStaysAsItIs() {
        let frame = CGRect(x: 100, y: 120, width: 1100, height: 760)
        #expect(WindowFit.fitted(frame, in: visible) == frame)
        #expect(WindowFit.fits(frame, in: visible))
    }

    @Test func aWindowTallerThanTheScreenFitsBetweenMenuBarAndDock() {
        // Top edge just under the menu bar, bottom 450 points below the Dock.
        let frame = CGRect(x: 40, y: -378, width: 1400, height: 1323)
        let fitted = WindowFit.fitted(frame, in: visible)
        #expect(fitted == CGRect(x: 40, y: 72, width: 1400, height: 873))
        #expect(!WindowFit.fits(frame, in: visible))
        #expect(WindowFit.fits(fitted, in: visible))
    }

    @Test func aRestoredWindowFillsTheScreensHeight() {
        // Restored from a bigger display, its top below the menu bar.
        let frame = CGRect(x: 0, y: -500, width: 1200, height: 1300)
        let fitted = WindowFit.fitted(frame, in: visible)
        #expect(fitted.height == visible.height)
        #expect(fitted.minY == visible.minY)
        #expect(fitted.maxY == visible.maxY)
    }

    @Test func aWindowHangingOffTheBottomMovesUpWithoutShrinking() {
        let frame = CGRect(x: 200, y: -100, width: 1000, height: 700)
        let fitted = WindowFit.fitted(frame, in: visible)
        #expect(fitted == CGRect(x: 200, y: 72, width: 1000, height: 700))
    }

    @Test func aWindowUnderTheMenuBarMovesDown() {
        let frame = CGRect(x: 200, y: 400, width: 1000, height: 700)
        let fitted = WindowFit.fitted(frame, in: visible)
        #expect(fitted.maxY == visible.maxY)
        #expect(fitted.height == 700)
    }

    @Test func aWindowWiderThanTheScreenShrinksAndComesBack() {
        let frame = CGRect(x: 300, y: 100, width: 2200, height: 700)
        let fitted = WindowFit.fitted(frame, in: visible)
        #expect(fitted == CGRect(x: 0, y: 100, width: 1512, height: 700))
    }

    @Test func aWindowOffTheRightEdgeMovesLeft() {
        let frame = CGRect(x: 900, y: 100, width: 1000, height: 700)
        #expect(WindowFit.fitted(frame, in: visible).maxX == visible.maxX)
    }

    @Test func aSecondDisplayToTheLeftWorksTheSame() {
        // Screens left of the main one have negative x.
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let frame = CGRect(x: -1800, y: -300, width: 1500, height: 1500)
        let fitted = WindowFit.fitted(frame, in: left)
        #expect(fitted == CGRect(x: -1800, y: 0, width: 1500, height: 1055))
    }

    @Test func nothingChangesWithoutAScreen() {
        let frame = CGRect(x: 0, y: -400, width: 1200, height: 2000)
        #expect(WindowFit.fitted(frame, in: .zero) == frame)
    }
}
