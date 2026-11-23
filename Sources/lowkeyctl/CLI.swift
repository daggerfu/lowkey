import Foundation
#if canImport(AppKit)
import AppKit
#endif
import BobukCore
import LowkeyCore

struct CLI {
    static let pageUsage = "\n       lowkeyctl <site-alias> <inspect|status> [--json]\n       lowkeyctl <site-alias> wait [label] [--timeout seconds]\n       lowkeyctl <site-alias> <fill|select> <label> <value>\n       lowkeyctl <site-alias> save-pdf <file.pdf>"
    static let usage = "Usage: lowkeyctl <site-alias> <toggle|open|hide|rewind>\n       lowkeyctl <site-alias> click \"<button or link label>\"\n       lowkeyctl <site-alias> upload <file> [--field \"<field label>\"]" + pageUsage

    static func readUpload(_ path: String, alias: String, field: String?) -> ControlRequest {
        guard Site.isValidAlias(alias) else { fail(usage, code: 64) }
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { fail("cannot open file") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else { fail("expected a regular file") }
        guard metadata.st_size <= ControlRequest.maximumFileSize else { fail("file exceeds 8 MiB") }
        // The size is validated above; readDataToEndOfFile stays usable on macOS 10.15.0-10.15.3.
        let bytes = file.readDataToEndOfFile()
        guard let request = ControlRequest(alias: alias, filename: URL(fileURLWithPath: path).lastPathComponent, bytes: bytes, field: field) else { fail("invalid filename, field label or file size") }
        return request
    }

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("lowkeyctl: \(message)\n".utf8))
        exit(code)
    }

    static func requestFromArguments() -> (ControlRequest, Int) {
        var args = Array(CommandLine.arguments.dropFirst())
        var waitSeconds = 10
        if args.count >= 2, args[1] == "wait", let i = args.dropFirst(2).firstIndex(of: "--timeout") {
            guard i + 2 == args.count, let n = Int(args[i+1]), (1...300).contains(n) else { fail(usage, code: 64) }
            args.removeLast(2); waitSeconds = n
        }
        if args.count == 3, args[1] == "save-pdf" {
            args[2] = URL(fileURLWithPath: (args[2] as NSString).expandingTildeInPath).standardizedFileURL.path
        }
        if args == ["--help"] || args == ["-h"] { print(usage); exit(0) }
        let request: ControlRequest
        if (args.count == 3 || (args.count == 5 && args[3] == "--field")), args[1] == "upload" {
            request = readUpload(args[2], alias: args[0], field: args.count == 5 ? args[4] : nil)
        }
        else if let parsed = ControlRequest(args) { request = parsed }
        else { fail(usage, code: 64) }
        return (request, waitSeconds)
    }

    static func finish(request: ControlRequest, name: String, waitUntil: Date,
                       activate: @escaping () -> Void) {
        func send() -> String {
            // Retry discovery, never the command: a timed-out toggle may already have run.
            switch MessagePortClient.send(request.payload, to: name, messageID: 1, sendTimeout: 1,
                                          timeout: request.command.isPDFExport ? 65 : 5) {
            case .success(let bytes): return String(decoding: bytes, as: UTF8.self)
            case .failure: fail("no reply from lowkey")
            }
        }
        var reply = send()
        if case .page(.wait, _) = request.command {
            while reply == "pending" {
                guard Date() < waitUntil else { fail("wait timed out") }
                usleep(120_000)
                reply = send()
            }
        }
        conclude(request: request, reply: reply, activate: activate)
    }

    static func conclude(request: ControlRequest, reply: String, activate: () -> Void) -> Never {
        if reply.hasPrefix("PDF export failed:") { fail(reply) }
        if reply.hasPrefix("output:") { print(reply.dropFirst(7)); exit(0) }
        switch reply {
        case "ok": exit(0)
        case "focus":
            activate()
            exit(0)
        case "unknown site": fail("unknown site: \(request.alias)")
        case "unsupported on linux", "inspection too large", "control read only", "multiple select unsupported", "option not found", "ambiguous option",
             "window not open", "wrong site origin", "label not found", "ambiguous label", "control disabled",
             "no file input", "multiple file inputs", "field not found", "ambiguous field", "file type not accepted", "directory input unsupported", "unsupported link", "page unavailable", "page loading", "result unknown": fail(reply)
        default: fail("command rejected by lowkey")
        }
    }

    static func main() {
        let (request, waitSeconds) = requestFromArguments()
        #if canImport(AppKit)
        macMain(request: request, waitSeconds: waitSeconds)
        #else
        linuxMain(request: request, waitSeconds: waitSeconds)
        #endif
    }

    // MARK: - macOS

    #if canImport(AppKit)
    static func macMain(request: ControlRequest, waitSeconds: Int) {
        guard let executable = Bundle.main.executableURL else { fail("cannot locate executable") }
        let app = executable.resolvingSymlinksInPath().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app", let id = Bundle(url: app)?.bundleIdentifier else {
            fail("run the helper inside lowkey.app/Contents/Helpers")
        }
        let client = NSWorkspace.shared
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: {
            $0.bundleURL?.resolvingSymlinksInPath().path == app.path
        }) {
            proceed(running, app: app, request: request, waitSeconds: waitSeconds)
        } else {
            if request.command == .window(.hide) { return }
            switch request.command {
            case .page(.status, let params): print(WindowStatus(alias: request.alias).output(json: params == ["--json"])); return
            case .page, .click, .upload: fail("window not open: \(request.alias)")
            case .window: break
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            client.openApplication(at: app, configuration: config) { target, error in
                if let error = error { fail(error.localizedDescription) }
                guard let target = target else { fail("cannot launch lowkey") }
                proceed(target, app: app, request: request, waitSeconds: waitSeconds)
            }
            // Keep the run loop alive for the openApplication completion handler.
            RunLoop.current.run()
        }
    }

    static func proceed(_ target: NSRunningApplication, app: URL, request: ControlRequest, waitSeconds: Int) {
        guard target.bundleURL?.resolvingSymlinksInPath().path == app.path else { fail("another copy of lowkey is running") }
        let name = ControlRequest.portName(pid: target.processIdentifier)
        // Stop waiting early when the app quits while starting.
        MessagePortClient.waitForServer(name, timeout: 4, keepWaiting: { !target.isTerminated }) { available in
            guard available else { fail("lowkey did not open its control port") }
            finish(request: request, name: name, waitUntil: Date().addingTimeInterval(TimeInterval(waitSeconds))) {
                if !target.isActive && !target.activate(options: []) { fail("macOS declined activation") }
            }
        }
        RunLoop.current.run()
    }
    #endif

    // MARK: - Linux

    #if !canImport(AppKit)
    static let pidFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("io.bobuk.lowkey.pid")

    /// The app binary: LOWKEY_BIN, then "lowkey" on PATH.
    static func linuxBinary() -> URL? {
        if let path = ProcessInfo.processInfo.environment["LOWKEY_BIN"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for dir in pathDirs {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("lowkey")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func runningPid() -> Int32? {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 1 else { return nil }
        return kill(pid, 0) == 0 ? pid : nil
    }

    static func linuxMain(request: ControlRequest, waitSeconds: Int) {
        if let pid = runningPid() {
            finish(request: request, name: ControlRequest.portName(pid: pid),
                   waitUntil: Date().addingTimeInterval(TimeInterval(waitSeconds)), activate: {})
            return
        }
        if request.command == .window(.hide) { return }
        switch request.command {
        case .page(.status, let params): print(WindowStatus(alias: request.alias).output(json: params == ["--json"])); return
        case .page, .click, .upload: fail("window not open: \(request.alias)")
        case .window: break
        }
        guard let binary = linuxBinary() else { fail("lowkey is not running and no binary was found (set LOWKEY_BIN)") }
        let process = Process()
        process.executableURL = binary
        do { try process.run() } catch { fail("cannot launch lowkey: \(error.localizedDescription)") }
        let pid = process.processIdentifier
        let name = ControlRequest.portName(pid: pid)
        MessagePortClient.waitForServer(name, timeout: 4, keepWaiting: { self.runningPid() == pid }) { available in
            guard available else { fail("lowkey did not open its control port") }
            finish(request: request, name: name, waitUntil: Date().addingTimeInterval(TimeInterval(waitSeconds)),
                   activate: {})
        }
        RunLoop.current.run()
    }
    #endif
}
