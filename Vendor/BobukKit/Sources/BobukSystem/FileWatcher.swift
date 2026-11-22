// Watches one file for changes from every editor, from Ting's config store: the folder (editors
// often replace the file) and the file itself (in-place saves), coalescing the burst of one save.
// macOS watches file descriptors; Linux polls the modification stamps on a timer.
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

#if canImport(Darwin)
private typealias FileSystemSource = DispatchSourceFileSystemObject
#else
// Linux never creates one (polling timer instead); the alias only stores the shared state.
private typealias FileSystemSource = DispatchSourceTimer
#endif

public final class FileWatcher {
    public let url: URL
    /// True for a folder watcher: the folder and every file directly in it.
    public let watchesFolder: Bool
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private var directorySource: FileSystemSource?
    private var fileSource: FileSystemSource?
    private var folderFileSources: [FileSystemSource] = []
    private var pending: DispatchWorkItem?

    /// Watches one file. Starts at once; the file may not exist yet, its folder must.
    public init(url: URL, debounce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.url = url
        watchesFolder = false
        self.debounce = debounce
        self.onChange = onChange
        directorySource = makeSource(path: url.deletingLastPathComponent().path)
        watchFile()
    }

    /// Watches a folder and every file directly in it: added, removed, renamed and edited files
    /// (Ting's micro-apps folder). The file list is read again after each change.
    public init(folder: URL, debounce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        url = folder
        watchesFolder = true
        self.debounce = debounce
        self.onChange = onChange
        directorySource = makeSource(path: folder.path)
        watchFile()
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
        for source in folderFileSources { source.cancel() }
        pending?.cancel()
        #if !canImport(Darwin)
        linuxTimer?.cancel()
        #endif
    }

    /// Call after the app itself wrote the file: an atomic write replaced the watched inode.
    public func fileWasReplaced() { watchFile() }

    public func stop() {
        directorySource?.cancel()
        fileSource?.cancel()
        for source in folderFileSources { source.cancel() }
        pending?.cancel()
        #if !canImport(Darwin)
        linuxTimer?.cancel()
        #endif
        directorySource = nil
        fileSource = nil
        folderFileSources = []
        #if !canImport(Darwin)
        linuxTimer = nil
        #endif
    }

    private func watchFile() {
        guard watchesFolder else {
            fileSource?.cancel()
            fileSource = makeSource(path: url.path)
            return
        }
        for source in folderFileSources { source.cancel() }
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        folderFileSources = files.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .compactMap { makeSource(path: $0.path) }
    }

    #if canImport(Darwin)
    private func makeSource(path: String) -> FileSystemSource? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .delete, .rename, .extend],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            self?.schedule()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.watchFile()
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }
    #else
    // Linux: libdispatch has no VNODE sources, so a timer polls the modification stamps.
    // `signature` captures everything watched; a difference is one coalesced change.
    private var linuxTimer: DispatchSourceTimer?
    private var linuxSignature: [String: Date]?

    private func makeSource(path: String) -> FileSystemSource? {
        if linuxTimer == nil {
            linuxSignature = linuxStamps()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: max(debounce, 0.05))
            timer.setEventHandler { [weak self] in self?.linuxPoll() }
            timer.resume()
            linuxTimer = timer
        }
        return nil
    }

    private func linuxPoll() {
        let stamp = linuxSignature ?? [:]
        let next = linuxStamps()
        guard next != stamp else { return }
        linuxSignature = next
        schedule()
    }

    private func linuxStamps() -> [String: Date] {
        func stamp(_ path: String) -> Date? {
            let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate
        }
        var result: [String: Date] = [:]
        if watchesFolder {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            for name in files {
                let path = url.appendingPathComponent(name).path
                if let date = stamp(path) { result[path] = date }
            }
        } else if let date = stamp(url.path) {
            result[url.path] = date
        }
        // A file replaced between polls (new inode, same name) still changes the folder's stamp;
        // watching the parent catches it even when the mtime resolution hides the file's own.
        if let parent = stamp(url.deletingLastPathComponent().path) {
            result[url.deletingLastPathComponent().path] = parent
        }
        return result
    }

    private func schedule() {
        watchFile()
        onChange()
    }
    #endif
}
