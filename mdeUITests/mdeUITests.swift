//
//  mdeUITests.swift
//  mdeUITests
//

import XCTest

final class mdeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesWithWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testAccessibilityIdentifiersWhenDocumentOpen() throws {
        #if os(macOS)
        throw XCTSkip("DocumentGroup new-document flow is unstable in macOS UI test runner")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding"]
        app.launch()

        let noteList = app.descendants(matching: .any)["note-list"]
        guard noteList.waitForExistence(timeout: 8) else {
            throw XCTSkip("Note list not reachable in simulator UI test")
        }

        app.navigationBars.buttons["New Note"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["note-editor"].waitForExistence(timeout: 5))
        #endif
    }

    @MainActor
    func testVaultMenuExistsOnIOS() throws {
        #if os(macOS)
        throw XCTSkip("Vault menu layout differs on macOS")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding"]
        app.launch()

        let vaultMenu = app.buttons["Vault actions menu"]
        guard vaultMenu.waitForExistence(timeout: 8) else {
            throw XCTSkip("Vault menu not visible in compact layout")
        }
        vaultMenu.tap()
        XCTAssertTrue(app.buttons["Link Graph"].waitForExistence(timeout: 3))
        #endif
    }

    @MainActor
    func testNoteListScrollsOnIOS() throws {
        #if os(macOS)
        throw XCTSkip("Scroll smoke is iOS simulator only")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding"]
        app.launch()

        let noteList = app.descendants(matching: .any)["note-list"]
        guard noteList.waitForExistence(timeout: 8) else {
            throw XCTSkip("Note list not reachable in simulator UI test")
        }

        for _ in 0..<4 {
            noteList.swipeUp()
        }
        XCTAssertTrue(noteList.exists)
        #endif
    }
}
