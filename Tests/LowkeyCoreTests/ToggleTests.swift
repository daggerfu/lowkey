import Foundation
import XCTest
@testable import LowkeyCore

final class ToggleTests: XCTestCase {
    func testParsesAliasAndWildcardToggle() throws {
        XCTAssertEqual(try DeepLink.parse(URL(string: "lowkey://HA/toggle")!).get(), .site(alias: "HA", command: .toggle))
        XCTAssertEqual(try DeepLink.parse(URL(string: "lowkey://*/toggle")!).get(), .site(alias: "*", command: .toggle))
        XCTAssertEqual(try DeepLink.parse(URL(string: "lowkey://ha/TOGGLE")!).get(), .site(alias: "ha", command: .toggle))
        XCTAssertEqual(DeepLink.parse(URL(string: "lowkey://HA/toggle/extra")!), .failure(.unknownCommand("toggle/extra")))
    }

    func testOnlyFrontmostVisibleWindowIsHidden() {
        for isVisible in [false, true] {
            for isMiniaturized in [false, true] {
                for isFrontmost in [false, true] {
                    let expected: WindowToggle = isVisible && !isMiniaturized && isFrontmost ? .hide : .show
                    XCTAssertEqual(WindowToggle.action(isVisible: isVisible, isMiniaturized: isMiniaturized,
                                                       isFrontmost: isFrontmost), expected)
                }
            }
        }
    }

    func testRestoresOtherWindowsBehindTheAppThatWasInFront() {
        let moves = WindowToggle.backgroundRestoration(before: [10, 2, 1, 3], after: [1, 3, 2, 10],
                                                       owned: [1, 2, 3], target: 1)
        XCTAssertEqual(moves.map(\.window), [3, 2])  // Reverse insertion preserves the original stack.
        XCTAssertEqual(moves.map(\.anchor), [10, 10])
    }

    func testHidingLetsOnlyWindowsAlreadyInFrontTakeFocus() {
        XCTAssertEqual(WindowToggle.backgroundWindows(in: [1, 2, 10, 3, 11, 4], owned: [1, 2, 3, 4]), [3, 4])
        XCTAssertTrue(WindowToggle.backgroundWindows(in: [1, 2], owned: [1, 2]).isEmpty)
    }

    func testLeavesWindowsThatDidNotCrossAnExternalWindowAlone() {
        let moves = WindowToggle.backgroundRestoration(before: [2, 10, 3, 1, 4, 5], after: [1, 2, 10, 3, 5],
                                                       owned: [1, 2, 3, 4, 5], target: 1)
        XCTAssertTrue(moves.isEmpty)  // Includes window 4, which is no longer onscreen.
    }

    func testRestoresSeparateGroupsAndSkipsVanishedAnchors() {
        let moves = WindowToggle.backgroundRestoration(before: [10, 2, 11, 3, 12, 4, 1],
                                                       after: [1, 4, 3, 10, 12, 2],
                                                       owned: [1, 2, 3, 4], target: 1)
        XCTAssertEqual(moves.map(\.window), [3, 2, 4])
        XCTAssertEqual(moves.map(\.anchor), [10, 10, 12])
    }

    func testWildcardHidesOnlyIfASavedWindowIsFrontmost() {
        XCTAssertEqual(WindowToggle.groupAction(frontmostWindows: [true, false]), .hide)
        XCTAssertEqual(WindowToggle.groupAction(frontmostWindows: [false, false]), .show)
        XCTAssertEqual(WindowToggle.groupAction(frontmostWindows: []), .show)
    }
}
