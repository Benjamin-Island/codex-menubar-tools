import CoreServices
import Foundation

final class SessionDirectoryMonitor: @unchecked Sendable {
    private let directory: URL
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var debounceTimer: Timer?

    init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard stream == nil else { return true }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }

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
            Self.eventCallback,
            &context,
            [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            return false
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
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

    private func scheduleChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                self?.onChange()
            }
        }
    }

    private static let eventCallback: FSEventStreamCallback = { _, callbackInfo, _, _, _, _ in
        guard let callbackInfo else { return }
        let monitor = Unmanaged<SessionDirectoryMonitor>
            .fromOpaque(callbackInfo)
            .takeUnretainedValue()
        monitor.scheduleChange()
    }
}
