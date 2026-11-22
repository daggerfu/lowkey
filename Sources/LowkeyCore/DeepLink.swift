import Foundation

/// Commands for a saved site: `lowkey://ALIAS/<command>`.
/// Deep links only drive navigation and windows; they never run page scripts.
public enum SiteCommand: String, CaseIterable {
    /// Show the site window; load the start page when the window is new.
    case open
    /// Show the site and load its configured start URL, even if its window already exists.
    case rewind
    /// Hide a visible window, or show/create the saved-site window.
    case toggle
    case reload
    case back
    case forward
    /// Go to the configured start URL.
    case start
    /// Hide the window and keep the live page.
    case hide
    /// Close the window and release the live page. The profile stays.
    case close
}

public enum DeepLink: Equatable {
    /// `lowkey://` with no alias: show the address prompt.
    case prompt
    case site(alias: String, command: SiteCommand)

    public enum ParseError: Error, Equatable {
        case notLowkey
        case unknownCommand(String)
    }

    public static let scheme = "lowkey"

    public static func parse(_ url: URL) -> Result<DeepLink, ParseError> {
        guard url.scheme?.lowercased() == scheme else { return .failure(.notLowkey) }
        guard let alias = url.host?.removingPercentEncoding, !alias.isEmpty else { return .success(.prompt) }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let name = parts.first else { return .success(.site(alias: alias, command: .open)) }
        guard parts.count == 1, let command = SiteCommand(rawValue: name.lowercased()) else {
            return .failure(.unknownCommand(parts.joined(separator: "/")))
        }
        return .success(.site(alias: alias, command: command))
    }

    public static func url(alias: String, command: SiteCommand = .open) -> String {
        "\(scheme)://\(alias)/\(command.rawValue)"
    }
}
