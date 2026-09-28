import XCTest

@MainActor
final class ChessTVUITests: XCTestCase {
    private var app: XCUIApplication!
    private var remote: XCUIRemote!

    func testHomeNavigationOpensNewGame() {
        launch()
        let titleExists = app.staticTexts["ChessTV"].waitForExistence(timeout: 5)
        XCTAssertTrue(titleExists)
        remote.press(.select)
        let newGameExists = app.staticTexts["New Game"].waitForExistence(timeout: 3)
        XCTAssertTrue(newGameExists)
    }

    func testRemoteCanStartAndMoveOnBoard() {
        launch()
        openGame()
        remote.press(.select) // e2
        remote.press(.up)     // e3
        remote.press(.select)
        let board = app.descendants(matching: .any)["chess-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 2))
        XCTAssertTrue(board.label.localizedCaseInsensitiveContains("e3, white pawn"))
    }

    func testOpenAndCloseGameMenu() {
        launch()
        openGame()
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["Game Menu"].waitForExistence(timeout: 2))
        remote.press(.select) // Resume has initial focus.
        XCTAssertFalse(app.staticTexts["Game Menu"].exists)
    }

    func testBackReturnsFromSettings() {
        launch()
        XCTAssertTrue(app.staticTexts["ChessTV"].waitForExistence(timeout: 5))
        remote.press(.down)
        remote.press(.right)
        remote.press(.select)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["ChessTV"].waitForExistence(timeout: 3))
    }

    private func openGame() {
        XCTAssertTrue(app.staticTexts["ChessTV"].waitForExistence(timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["New Game"].waitForExistence(timeout: 3))
        focusAndSelect(app.buttons["Start Game"], moving: .down)
        let status = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'White to move'")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 4))
    }

    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        remote = XCUIRemote.shared
    }

    private func focusAndSelect(_ element: XCUIElement, moving direction: XCUIRemote.Button, attempts: Int = 10) {
        for _ in 0..<attempts where !element.hasFocus { remote.press(direction) }
        XCTAssertTrue(element.hasFocus, "Could not focus \(element)")
        remote.press(.select)
    }
}
