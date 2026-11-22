import BobukCore
import Foundation

/// Versioned, login-session-local control channel. One port per running copy.
public struct ControlRequest {
    public enum Command: Equatable {
        case window(SiteCommand)
        case page(PageCommand, [String])
        case click(String)
        case upload(name: String, bytes: Data, field: String? = nil)

        public var isPDFExport: Bool {
            if case .page(.savePDF, _) = self { return true }
            return false
        }
    }
    public static let maximumFileSize = 8 * 1024 * 1024
    public let command: Command
    public let alias: String

    public init?(_ arguments: [String]) {
        guard arguments.count >= 2, Site.isValidAlias(arguments[0]) else { return nil }
        alias = arguments[0]
        if let verb = PageCommand(rawValue: arguments[1]) {
            let args = Array(arguments.dropFirst(2))
            guard args.allSatisfy({ $0.utf8.count <= 16384 && !$0.utf8.contains(0) }) else { return nil }
            switch verb {
            case .savePDF: guard args.count == 1, args[0].hasPrefix("/"), args[0].lowercased().hasSuffix(".pdf") else { return nil }
            case .inspect, .status: guard args.isEmpty || args == ["--json"] else { return nil }
            case .wait: guard args.isEmpty || (args.count == 1 && !args[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return nil }
            case .fill, .select: guard args.count == 2 && !args[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            }
            command = .page(verb, args)
        } else if arguments.count == 3, arguments[1] == "click" {
            let label = arguments[2]
            guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  label.utf8.count <= 1024, !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            command = .click(label)
        } else {
            guard arguments.count == 2, let action = SiteCommand(rawValue: arguments[1]),
                  [.open, .hide, .toggle, .rewind].contains(action) else { return nil }
            command = .window(action)
        }
    }

    public init?(alias: String, filename: String, bytes: Data, field: String? = nil) {
        if let field = field {
            guard !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, field.utf8.count <= 1024,
                  !field.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        }
        guard Site.isValidAlias(alias), !filename.isEmpty, filename.utf8.count <= 255,
              filename != ".", filename != "..", !filename.contains("/"),
              !filename.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              bytes.count <= Self.maximumFileSize else { return nil }
        self.alias = alias
        command = .upload(name: filename, bytes: bytes, field: field)
    }

    /// `io.bobuk.lowkey.control.v1.<pid>`.
    public static func portName(pid: Int32) -> String {
        MessagePortServer.name(prefix: "io.bobuk.lowkey.control", version: 1, pid: pid)
    }
    public var payload: Data {
        switch command {
        case .page(let verb, let args): return Data("page ".utf8) + ((try? JSONEncoder().encode([alias, verb.rawValue] + args)) ?? Data())
        case .click(let label): return Data("click \(alias) \(label)".utf8)
        case .window(let action): return Data("\(action.rawValue) \(alias)".utf8)
        case .upload(let name, let bytes, let field):
            return Data((field.map { "upload-field \(alias) \(name)\0\($0)\0" } ?? "upload \(alias) \(name)\0").utf8) + bytes
        }
    }
    public init?(payload: Data) {
        // The wire format remains verb-first for existing v1 clients. Uploads carry bytes, never paths.
        if payload.starts(with: "page ".utf8) {
            guard payload.count <= 210_000, let args = try? JSONDecoder().decode([String].self, from: payload.dropFirst(5)),
                  args.count >= 2, PageCommand(rawValue: args[1]) != nil else { return nil }
            self.init(args)
            return
        }
        let named = payload.starts(with: "upload-field ".utf8)
        if named || payload.starts(with: "upload ".utf8) {
            guard payload.count <= Self.maximumFileSize + 1330,
                  let end = payload.prefix(301).firstIndex(of: 0), let text = String(data: payload[..<end], encoding: .utf8) else { return nil }
            let parts = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            var body = payload.suffix(from: end + 1)
            var field: String?
            if named {
                guard let separator = body.prefix(1025).firstIndex(of: 0),
                      let label = String(data: body[..<separator], encoding: .utf8) else { return nil }
                field = label
                body = body.suffix(from: separator + 1)
            }
            self.init(alias: String(parts[1]), filename: String(parts[2]), bytes: body, field: field)
        } else {
            guard payload.count <= 1063, let text = String(data: payload, encoding: .utf8) else { return nil }
            var args = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard args.count >= 2 else { return nil }
            args.swapAt(0, 1)
            self.init(args)
        }
    }
}
