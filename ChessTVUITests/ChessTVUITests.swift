import XCTest

@MainActor
final class ChessTVUITests: XCTestCase {
    private var app: XCUIApplication!
    private var remote: XCUIRemote!

    func testHomeShowsPlayBots() {
        launch()
        XCTAssertTrue(playBots.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.playFriend"].exists)
        XCTAssertTrue(app.buttons["home.puzzles"].exists)
    }

    func testPlayFriendStartsGameAndMenuReturnsHome() {
        launch()
        XCTAssertTrue(playBots.waitForExistence(timeout: 5))
        focusAndSelect(app.buttons["home.playFriend"], moving: .down)

        let startGame = app.buttons["Start Game"]
        XCTAssertTrue(startGame.waitForExistence(timeout: 3))
        focusAndSelect(startGame, moving: .down)

        let board = app.descendants(matching: .any)["chess-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 4))

        remote.press(.menu)
        XCTAssertTrue(playBots.waitForExistence(timeout: 3))
    }

    func testMenuReturnsFromSettings() {
        launch()
        XCTAssertTrue(playBots.waitForExistence(timeout: 5))
        focusAndSelect(app.buttons["sidebar.settings"], moving: .left, then: .down)
        XCTAssertTrue(app.buttons["Show Legal Moves"].waitForExistence(timeout: 3))
        remote.press(.menu)
        XCTAssertTrue(playBots.waitForExistence(timeout: 3))
    }

    private var playBots: XCUIElement { app.buttons["home.playBots"] }

    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        remote = XCUIRemote.shared
    }

    /// Presses `direction` until `element` has focus (then `then`, if given), and selects it.
    private func focusAndSelect(
        _ element: XCUIElement,
        moving direction: XCUIRemote.Button,
        then next: XCUIRemote.Button? = nil,
        attempts: Int = 10
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing \(element)")
        var pressedFirst = false
        for _ in 0..<attempts where !element.hasFocus {
            if let next, pressedFirst {
                remote.press(next)
            } else {
                remote.press(direction)
                pressedFirst = true
            }
        }
        XCTAssertTrue(element.hasFocus, "Could not focus \(element)")
        remote.press(.select)
    }
}
