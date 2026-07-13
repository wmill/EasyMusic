import XCTest

// Drives the JamView width-resize feature end-to-end: 1:1 handle tracking,
// clamping at both extremes, right-handle symmetry, and AppStorage persistence.
final class JamResizeDriverTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testResizeDrag() throws {
        let app = XCUIApplication()
        app.launch()

        navigateToJamView(app)

        let resizeButton = app.buttons["Resize jam width"]
        XCTAssertTrue(resizeButton.waitForExistence(timeout: 10), "resize button missing")
        resizeButton.tap()

        let leftHandle = app.otherElements["Left jam width handle"].firstMatch
        XCTAssertTrue(leftHandle.waitForExistence(timeout: 5), "left handle missing after unlock")

        let screenWidth = app.frame.width

        // Normalize state (padding may persist from earlier runs): clamp far left to
        // padding 0. The grid's leading edge then sits at the safe-area inset.
        drag(leftHandle, byX: -600, velocity: 400, endHold: 0.2)
        let minXMin = firstColumnKeyMinX(app)
        NSLog("DRIVER clamp-left leading edge (safe-area inset): \(minXMin)")

        // Slow drag +100pt with a hold at the end so external screenshots can
        // catch the placeholder grid mid-gesture.
        drag(leftHandle, byX: 100, velocity: 60, endHold: 2.0)
        let minX1 = firstColumnKeyMinX(app)
        NSLog("DRIVER after +100 drag leading edge: \(minX1)")
        XCTAssertEqual(minX1 - minXMin, 100, accuracy: 8, "leading edge should track the finger 1:1")

        // Probe: drag far right — padding must clamp at 25% of the safe-area width
        // (grid never narrower than half the available width).
        drag(leftHandle, byX: 600, velocity: 400, endHold: 0.2)
        let minXMax = firstColumnKeyMinX(app)
        let expectedMaxPadding = (screenWidth - 2 * minXMin) * 0.25
        NSLog("DRIVER after clamp-right drag leading edge: \(minXMax), screen \(screenWidth), inset \(minXMin)")
        XCTAssertEqual(minXMax - minXMin, expectedMaxPadding, accuracy: 8, "padding should clamp at quarter of available width")

        // Probe: right handle dragged outward from max clamp shrinks padding symmetrically.
        let rightHandle = app.otherElements["Right jam width handle"].firstMatch
        XCTAssertTrue(rightHandle.exists, "right handle missing")
        drag(rightHandle, byX: 80, velocity: 200, endHold: 0.2)
        let minX2 = firstColumnKeyMinX(app)
        NSLog("DRIVER after right-handle +80 drag leading edge: \(minX2)")
        XCTAssertEqual(minXMax - minX2, 80, accuracy: 8, "right handle should track 1:1")

        // Probe: padding persists across relaunch (written to AppStorage on release).
        app.terminate()
        app.launch()
        navigateToJamView(app)
        let minXRelaunch = firstColumnKeyMinX(app)
        NSLog("DRIVER after relaunch leading edge: \(minXRelaunch)")
        XCTAssertEqual(minXRelaunch, minX2, accuracy: 8, "padding should persist across launches")

        // Keys still play: press one and make sure the app doesn't blow up.
        app.buttons["Resize jam width"].tap() // leave resize mode
        firstColumnKey(app).press(forDuration: 0.4)
        XCTAssertTrue(app.buttons["Resize jam width"].exists)
    }

    @MainActor
    private func navigateToJamView(_ app: XCUIApplication) {
        let firstInstrument = app.collectionViews.buttons.element(boundBy: 0)
        XCTAssertTrue(firstInstrument.waitForExistence(timeout: 15), "instrument list missing")
        firstInstrument.tap()

        let keyC = app.buttons["C"].firstMatch
        XCTAssertTrue(keyC.waitForExistence(timeout: 15), "key selection missing")
        keyC.tap()
    }

    // The leftmost column of jam keys is the key's root ("C"), which collides with
    // the navigation title, so filter to elements below the nav bar.
    @MainActor
    private func firstColumnKey(_ app: XCUIApplication) -> XCUIElement {
        let candidates = app.staticTexts.matching(NSPredicate(format: "label == 'C'")).allElementsBoundByIndex
        let keys = candidates.filter { $0.frame.minY > 150 }
        XCTAssertFalse(keys.isEmpty, "no jam key labelled C below the nav bar")
        return keys.min { $0.frame.minY < $1.frame.minY }!
    }

    @MainActor
    private func firstColumnKeyMinX(_ app: XCUIApplication) -> CGFloat {
        firstColumnKey(app).frame.minX
    }

    @MainActor
    private func drag(_ element: XCUIElement, byX dx: CGFloat, velocity: CGFloat, endHold: TimeInterval) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: dx, dy: 0))
        start.press(
            forDuration: 0.3,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(rawValue: velocity),
            thenHoldForDuration: endHold
        )
    }
}
