#if canImport(AppKit)
import AppKit
import BobukCore
import SwiftUI

private struct HighlightRun {
    let text: String
    let marked: Bool
}

/// Splits by `Character` offsets, as in `FuzzyMatch.positions`.
private func highlightedRuns(_ text: String, positions: [Int]) -> [HighlightRun] {
    let marked = Set(positions)
    var runs: [HighlightRun] = []
    var run = ""
    var runMarked = false
    func flush() {
        guard !run.isEmpty else { return }
        runs.append(HighlightRun(text: run, marked: runMarked))
        run = ""
    }
    for (offset, character) in text.enumerated() {
        let isMarked = marked.contains(offset)
        if isMarked != runMarked { flush(); runMarked = isMarked }
        run.append(character)
    }
    flush()
    return runs
}

private func highlightPositions(_ text: String, query: String) -> [Int] {
    let prepared = FuzzyQuery(query)
    let match = prepared.match(text) ?? prepared.match(text, fallback: true)
    return match?.positions ?? []
}

public extension NSAttributedString {
    /// `text` with the characters at `positions` bold and, when given, in `color`.
    /// Marked runs carry a bold font and `.foregroundColor`; unmarked runs keep the base attributes.
    static func highlighting(_ text: String, positions: [Int], color: NSColor? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        var location = 0
        for run in highlightedRuns(text, positions: positions) {
            let length = (run.text as NSString).length
            if run.marked {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                ]
                if let color = color { attributes[.foregroundColor] = color }
                result.addAttributes(attributes, range: NSRange(location: location, length: length))
            }
            location += length
        }
        return result
    }

    /// `text` with the letters that `query` matched highlighted (also by the fallback pass of a
    /// 3-letter query); plain when nothing matched.
    static func highlighting(_ text: String, query: String, color: NSColor? = nil) -> NSAttributedString {
        highlighting(text, positions: highlightPositions(text, query: query), color: color)
    }
}

public extension Text {
    /// SwiftUI composition with the same runs as `NSAttributedString.highlighting`. It keeps the
    /// font of the enclosing `Text` and only adds bold (and color, when given) to matched runs.
    static func highlighting(_ text: String, positions: [Int], color: Color? = nil) -> Text {
        var result = Text("")
        for run in highlightedRuns(text, positions: positions) {
            var piece = Text(run.text)
            if run.marked {
                piece = piece.fontWeight(.bold)
                if let color = color { piece = piece.foregroundColor(color) }
            }
            result = result + piece
        }
        return result
    }

    /// Matches by `query` and composes the highlighted text as a SwiftUI `Text`.
    static func highlighting(_ text: String, query: String, color: Color? = nil) -> Text {
        highlighting(text, positions: highlightPositions(text, query: query), color: color)
    }
}
#endif
