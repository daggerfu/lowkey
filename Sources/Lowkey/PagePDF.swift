import AppKit
import WebKit

/// Use WebKit's print layout, including print CSS and every printed page, not a viewport snapshot.
enum PagePDF {
    private static var isPrinting = false

    enum Failure: LocalizedError {
        case printing
        var errorDescription: String? { "Could not save the page as PDF." }
    }

    private final class PrintJob: NSObject {
        private var completion: ((Bool) -> Void)?

        func run(_ operation: NSPrintOperation, in window: NSWindow, completion: @escaping (Bool) -> Void) {
            self.completion = completion
            operation.runModal(for: window, delegate: self,
                didRun: #selector(finished(_:success:context:)), contextInfo: nil)
        }

        @objc private func finished(_ operation: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) {
            completion?(success)
            completion = nil
        }
    }

    static func save(_ view: WKWebView, to destination: URL, overwrite: Bool = false,
                     completion: @escaping (Error?) -> Void) {
        guard !isPrinting else { completion(Failure.printing); return }
        isPrinting = true
        if !overwrite, FileManager.default.fileExists(atPath: destination.path) {
            isPrinting = false
            completion(CocoaError(.fileWriteFileExists))
            return
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) }
        catch { isPrinting = false; completion(error); return }
        let temporary = directory.appendingPathComponent("page.pdf")
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595.28, height: 841.89) // A4 in points; no printer required.
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = temporary
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        // WKWebView.printOperation(with:) needs macOS 11; on Catalina print the view directly
        // (single-page layout instead of WebKit's full pagination).
        let operation: NSPrintOperation
        #if compiler(>=5.4)
        if #available(macOS 11, *) {
            operation = view.printOperation(with: info)
        } else {
            operation = NSPrintOperation(view: view, printInfo: info)
        }
        #else
        operation = NSPrintOperation(view: view, printInfo: info)
        #endif
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // WebKit prepares pagination asynchronously. Synchronous run() can print endlessly.
        let job = PrintJob()
        let window = view.window ?? NSWindow(contentRect: view.bounds, styleMask: [], backing: .buffered, defer: false)
        job.run(operation, in: window) { success in
            defer { isPrinting = false; try? FileManager.default.removeItem(at: directory) }
            guard success, FileManager.default.fileExists(atPath: temporary.path) else { completion(Failure.printing); return }
            do {
                let data = try Data(contentsOf: temporary)
                try data.write(to: destination, options: overwrite ? .atomic : .withoutOverwriting)
                completion(nil)
            } catch { completion(error) }
        }
    }

    static func chooseDestination(for view: WKWebView, in window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["pdf"]
        panel.nameFieldStringValue = (view.title?.isEmpty == false ? view.title! : "Page")
            .replacingOccurrences(of: "/", with: "-") + ".pdf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            save(view, to: url, overwrite: true) { error in
                guard let error = error else { return }
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }
}
