import Foundation

public enum PageCommand: String { case inspect, status, wait, fill, select
    case savePDF = "save-pdf" }

public struct WindowStatus: Encodable {
    public let alias: String
    public let open, visible, minimized, focused, loading: Bool
    public init(alias: String, open: Bool = false, visible: Bool = false, minimized: Bool = false, focused: Bool = false, loading: Bool = false) {
        self.alias = alias; self.open = open; self.visible = visible; self.minimized = minimized; self.focused = focused; self.loading = loading
    }
    public func output(json: Bool) -> String {
        if json { return String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self) }
        return "\(alias): " + (!open ? "closed" : minimized ? "minimized" : !visible ? "hidden" : focused ? "focused" : "visible") + (loading ? ", loading" : "")
    }
}
