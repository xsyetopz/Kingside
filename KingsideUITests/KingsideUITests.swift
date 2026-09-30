import XCTest

/// Launch-to-board smoke tests. `--uitesting` gives each run empty storage, no sound, and no
/// Game Center or welcome sheet. Elements are found by accessibility identifier, not by text.
@MainActor
final class KingsideUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    func testPlayHomeOffersBotsAndPassAndPlay() {
        XCTAssertTrue(element("play.bots").waitForExistence(timeout: 10))
        XCTAssertTrue(element("play.passAndPlay").exists)
    }

    func testPassAndPlayStartsAGameAndBackReturnsToSetup() {
        XCTAssertTrue(element("play.passAndPlay").waitForExistence(timeout: 10))
        activate(element("play.passAndPlay"))

        let start = element("setup.start")
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        activate(start)

        XCTAssertTrue(element("board").waitForExistence(timeout: 10))

        goBack()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    #if os(tvOS)
    /// Moves focus down, and right along a row of cards once down goes no further, until
    /// `element` has it, then selects it. Down comes first: right in the tab bar switches tabs.
    private func activate(_ element: XCUIElement, attempts: Int = 30) {
        let remote = XCUIRemote.shared
        for _ in 0..<attempts where !isFocused(element) {
            let before = focusedFrame
            remote.press(.down)
            if focusedFrame == before { remote.press(.right) }
        }
        XCTAssertTrue(isFocused(element), "Could not focus \(element)")
        remote.press(.select)
    }

    private var focusedFrame: CGRect {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.frame : .null
    }

    /// In a list, focus lands on the cell that contains the identified element.
    private func isFocused(_ element: XCUIElement) -> Bool {
        if element.hasFocus { return true }
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists && focused.descendants(matching: .any)[element.identifier].exists
    }

    private func goBack() {
        XCUIRemote.shared.press(.menu)
    }
    #else
    /// On macOS `tap()` does not reach SwiftUI buttons; a click does.
    private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    /// macOS has no navigation bar; the back button sits in the window toolbar.
    private func goBack() {
        #if os(macOS)
        let back = app.toolbars.buttons["chevron.backward"].firstMatch
        #else
        let back = app.navigationBars.buttons.firstMatch
        #endif
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        activate(back)
    }
    #endif
}
