import AppKit
import WebKit

/// XCTest replacements for the Swift Testing helpers the modern manifest uses.
/// Everything runs on the main thread; `pump` keeps the run loop turning so WebKit
/// callbacks (delivered on the main queue) fire even while a test waits synchronously.
enum UITest {
    static func onMain<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }

    /// Runs the current run loop until `condition` holds or `timeout` passes.
    static func pump(until condition: () -> Bool, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// Synchronous `evaluateJavaScript`, safe on the main thread.
    @discardableResult
    static func evaluate(_ view: WKWebView, _ script: String) throws -> Any? {
        var result: Any?
        var failure: Error?
        var done = false
        view.evaluateJavaScript(script) { value, error in
            result = value
            failure = error
            done = true
        }
        pump(until: { done })
        if let failure = failure { throw failure }
        return result
    }

    /// Loads HTML with a real http(s) document URL (loadHTMLString uses baseURL as the
    /// document URL, so `location.origin` matches), then waits for the load to settle.
    static func loadPage(_ view: WKWebView, html: String, baseURL: URL) {
        view.loadHTMLString(html, baseURL: baseURL)
        pump(until: { !view.isLoading })
    }
}
