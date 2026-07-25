import CoreServices
import Foundation

final class PetConfigurationMonitor: @unchecked Sendable {
    private let configURL: URL
    private let petRoots: [URL]
    private let onChange: @MainActor () -> Void
    private var stream: FSEventStreamRef?
    private var debounceTimer: Timer?

    private static let eventDebounce: TimeInterval = 0.35

    init(
        configURL: URL,
        petRoots: [URL],
        onChange: @escaping @MainActor () -> Void
    ) {
        self.configURL = configURL.standardizedFileURL
        self.petRoots = petRoots.map(\.standardizedFileURL)
        self.onChange = onChange
    }

    deinit { stop() }

    @discardableResult
    func start() -> Bool {
        guard stream == nil else { return true }
        let paths = watchedDirectories().map(\.path)
        guard !paths.isEmpty else { return false }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            return false
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        self.stream = nil
    }

    private func watchedDirectories() -> [URL] {
        let candidates = [configURL.deletingLastPathComponent()]
            + petRoots.flatMap { root in
                [root, root.deletingLastPathComponent()]
            }
        var seen: Set<String> = []
        return candidates.filter { candidate in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: candidate.path,
                isDirectory: &isDirectory
            )
                && isDirectory.boolValue
                && seen.insert(candidate.path).inserted
        }
    }

    private func receivesRelevantChange(at eventPath: String) -> Bool {
        let path = URL(fileURLWithPath: eventPath).standardizedFileURL.path
        if path == configURL.path {
            return true
        }
        return petRoots.contains { root in
            path == root.path
                || path.hasPrefix(root.path + "/")
        }
    }

    private func receive(eventPaths: [String]) {
        guard eventPaths.contains(where: receivesRelevantChange(at:)) else { return }
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: Self.eventDebounce,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.debounceTimer = nil
            Task { @MainActor in self.onChange() }
        }
    }

    private static let callback: FSEventStreamCallback = {
        _, info, count, eventPaths, _, _ in
        guard let info,
              let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String]
        else {
            return
        }
        let deliveredPaths = Array(paths.prefix(Int(count)))
        Unmanaged<PetConfigurationMonitor>
            .fromOpaque(info)
            .takeUnretainedValue()
            .receive(eventPaths: deliveredPaths)
    }
}
