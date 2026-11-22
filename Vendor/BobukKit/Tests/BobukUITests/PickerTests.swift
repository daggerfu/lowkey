#if canImport(AppKit)
import AppKit
import BobukCore
import SwiftUI
import XCTest
@testable import BobukUI

final class PickerSelectionTests: XCTestCase {
    func testClampsWithoutWrapping() {
        XCTAssertEqual(PickerSelection.move(0, by: -1, count: 3), 0)
        XCTAssertEqual(PickerSelection.move(2, by: 1, count: 3), 2)
        XCTAssertEqual(PickerSelection.move(1, by: -1, count: 3), 0)
        XCTAssertEqual(PickerSelection.move(1, by: 1, count: 3), 2)
        XCTAssertEqual(PickerSelection.move(0, by: 1, count: 0), nil)
    }

    func testOptionalSelectionReturnsToTypedInput() {
        XCTAssertEqual(PickerSelection.move(nil, by: -1, count: 2, allowsEmpty: true), nil)
        XCTAssertEqual(PickerSelection.move(nil, by: 1, count: 2, allowsEmpty: true), 0)
        XCTAssertEqual(PickerSelection.move(0, by: -1, count: 2, allowsEmpty: true), nil)
        XCTAssertEqual(PickerSelection.move(1, by: 1, count: 2, allowsEmpty: true), 1)
        XCTAssertEqual(PickerSelection.move(20, by: 0, count: 2), 1)
    }

    func testExtremeInputDoesNotOverflow() {
        XCTAssertEqual(PickerSelection.move(Int.max, by: Int.max, count: 3), 2)
        XCTAssertEqual(PickerSelection.move(Int.min, by: Int.min, count: 3), 0)
    }
}

final class PickerGeometryTests: XCTestCase {
    func testBadgeColumnUsesOneMeasuredWidthAndCapsLongAliases() {
        XCTAssertEqual(PickerMetrics.badgeWidth(for: []), 44)
        XCTAssert(PickerMetrics.badgeWidth(for: ["HA", "NOCLAWS"]) >= 54)
        XCTAssertEqual(PickerMetrics.badgeWidth(for: [String(repeating: "W", count: 200)]), 96)
    }

    func testFooterWrapsWholeGroupsWithoutOverlap() {
        let frames = HintPacking.frames(sizes: [.init(width: 120, height: 12), .init(width: 100, height: 12),
                                                .init(width: 90, height: 24)], width: 240)
        XCTAssertEqual(frames[0].minY, frames[1].minY)
        XCTAssert(frames[2].minY >= frames[0].maxY + PickerMetrics.footerLineSpacing)
        XCTAssert(frames[0].maxX + PickerMetrics.footerSpacing <= frames[1].minX)
        XCTAssert(frames.allSatisfy { $0.maxX <= 240 })
        XCTAssert(HintPacking.frames(sizes: [], width: 0).isEmpty)
    }

    func testHostingSizesAgreeForDifferentBadgeLengths() {
        _ = NSApplication.shared
        let palette = PickerPalette(surface: .white, text: .black, secondary: .gray,
                                     accent: .blue, border: .gray, badgeInk: .white)
        let width = PickerMetrics.badgeWidth(for: ["HA", "NOCLAWS"])
        for text in ["HA", "NOCLAWS", String(repeating: "long", count: 20)] {
            let badge = NSHostingView(rootView: PickerBadge(text, width: width, palette: palette))
            XCTAssert(abs(badge.fittingSize.width - width) < 0.01)
            XCTAssert(abs(badge.fittingSize.height - PickerMetrics.badgeHeight) < 0.01)
        }
        let row = NSHostingView(rootView: PickerRow(selected: true, palette: palette) {
            Text("A row").frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 300))
        XCTAssert(abs(row.fittingSize.height - PickerMetrics.rowHeight) < 0.01)

        let footerWithSettings = NSHostingView(rootView: ShortcutFooter([.init("esc", "close")],
                                                                         palette: palette, onSettings: {}).frame(width: 300))
        XCTAssert(footerWithSettings.fittingSize.height >= 22)
    }
}

final class FuzzyHighlightTests: XCTestCase {
    private struct Run {
        let text: String
        let marked: Bool
        let color: NSColor?
    }

    /// 10.15-safe replacement for the 12+ attributed-string highlighter: `FuzzyQuery` supplies the
    /// very same character offsets the kit highlighter uses (including its fallback pass),
    /// and the runs below carry the same bold/color information as the attributed string.
    private func highlightedRuns(_ text: String, query: String, color: NSColor? = nil) -> [Run] {
        let prepared = FuzzyQuery(query)
        let match = prepared.match(text) ?? prepared.match(text, fallback: true)
        return highlightedRuns(text, positions: match?.positions ?? [], color: color)
    }

    private func highlightedRuns(_ text: String, positions: [Int], color: NSColor?) -> [Run] {
        let marked = Set(positions)
        var runs: [Run] = []
        var current = ""
        var currentMarked = false
        func flush() {
            guard !current.isEmpty else { return }
            runs.append(Run(text: current, marked: currentMarked, color: currentMarked ? color : nil))
            current = ""
        }
        for (offset, character) in text.enumerated() {
            let isMarked = marked.contains(offset)
            if isMarked != currentMarked { flush(); currentMarked = isMarked }
            current.append(character)
        }
        flush()
        return runs
    }

    func testMarksMatchedCharactersInRuns() {
        XCTAssertEqual(FuzzyQuery("1pwd").match("1Password")?.positions, [0, 1, 5, 8])
        let runs = highlightedRuns("1Password", query: "1pwd", color: .orange)
        XCTAssertEqual(runs.map { $0.text }, ["1P", "ass", "w", "or", "d"])
        XCTAssertEqual(runs.map { $0.marked }, [true, false, true, false, true])
        XCTAssertEqual(runs.first?.color, .orange)
    }

    func testFallbackMatchIsHighlighted() {
        let runs = highlightedRuns("1Password", query: "1pv")
        XCTAssertTrue(runs.contains { $0.marked })
    }

    func testPlainWithoutMatch() {
        let runs = highlightedRuns("Safari", query: "xyz")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.map { $0.text }.joined(), "Safari")
        XCTAssertFalse(runs.first?.marked ?? false)
    }
}
#endif
