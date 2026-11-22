/// Visibility policy shared by single-site and wildcard toggle commands.
public enum WindowToggle: Equatable {
    case hide, show

    public static func action(isVisible: Bool, isMiniaturized: Bool, isFrontmost: Bool) -> WindowToggle {
        isVisible && !isMiniaturized && isFrontmost ? .hide : .show
    }

    /// The wildcard hides the group only when one of its windows is frontmost.
    public static func groupAction(frontmostWindows: [Bool]) -> WindowToggle {
        frontmostWindows.contains(true) ? .hide : .show
    }

    /// Windows behind another app are not candidates for focus when a target is hidden.
    public static func backgroundWindows(in stack: [Int], owned: Set<Int>) -> Set<Int> {
        Set(stack.drop(while: { owned.contains($0) }).filter { owned.contains($0) })
    }

    /// Restore only groups of windows that were lifted above their previous external neighbor.
    /// Both stacks are in front-to-back order and contain only visible windows at the same level.
    public static func backgroundRestoration(before: [Int], after: [Int], owned: Set<Int>,
                                             target: Int) -> [(window: Int, anchor: Int)] {
        let ranks = Dictionary(uniqueKeysWithValues: after.enumerated().map { ($1, $0) })
        var anchor: Int?
        var group: [Int] = []
        var moves: [(window: Int, anchor: Int)] = []

        func endGroup() {
            if let anchor = anchor, let rank = ranks[anchor], group.contains(where: { ranks[$0, default: .max] < rank }) {
                moves += group.reversed().map { ($0, anchor) }
            }
            group.removeAll()
        }

        for window in before where window != target && ranks[window] != nil {
            if owned.contains(window) {
                group.append(window)
            } else {
                endGroup()
                anchor = window
            }
        }
        endGroup()
        return moves
    }
}
