import Darwin
import Foundation

struct DarwinBSDInfo: Equatable, Sendable {
    let pid: Int32
    let parentPID: Int32
    let userID: UInt32
    let startedAt: Date
    let hasControllingTerminal: Bool
}

struct DarwinOpenFile: Equatable, Sendable {
    let path: String
    let openFlags: Int32
}

protocol DarwinProcessReading: Sendable {
    func allPIDs() throws -> [Int32]
    func bsdInfo(pid: Int32) throws -> DarwinBSDInfo
    func executablePath(pid: Int32) throws -> String
    func arguments(pid: Int32) throws -> [String]
    func workingDirectory(pid: Int32) throws -> String?
    func openFiles(pid: Int32) throws -> [DarwinOpenFile]
}

public final class DarwinProcessProvider: ProcessProviding, @unchecked Sendable {
    private let reader: any DarwinProcessReading
    private let sessionsDirectoryPath: String

    public convenience init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    ) {
        self.init(reader: LibProcProcessReader(), sessionsDirectory: sessionsDirectory)
    }

    init(reader: any DarwinProcessReading, sessionsDirectory: URL) {
        self.reader = reader
        sessionsDirectoryPath = sessionsDirectory.standardizedFileURL.path
    }

    public func processSnapshots() throws -> [ProcessSnapshot] {
        let pids = try reader.allPIDs()
        return pids.compactMap(snapshot)
    }

    private func snapshot(pid: Int32) -> ProcessSnapshot? {
        do {
            let info = try reader.bsdInfo(pid: pid)
            let openFilePaths = try reader.openFiles(pid: pid)
                .filter { isWritable($0.openFlags) && isSessionLog($0.path) }
                .map(\.path)

            return ProcessSnapshot(
                pid: info.pid,
                parentPID: info.parentPID,
                userID: info.userID,
                startedAt: info.startedAt,
                executablePath: try reader.executablePath(pid: pid),
                arguments: try reader.arguments(pid: pid),
                workingDirectory: try reader.workingDirectory(pid: pid),
                hasControllingTerminal: info.hasControllingTerminal,
                openFilePaths: openFilePaths
            )
        } catch {
            // Processes can exit between enumeration and inspection.
            return nil
        }
    }

    private func isWritable(_ flags: Int32) -> Bool {
        let accessMode = flags & O_ACCMODE
        return accessMode == O_WRONLY || accessMode == O_RDWR
    }

    private func isSessionLog(_ path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let directoryPrefix = sessionsDirectoryPath.hasSuffix("/")
            ? sessionsDirectoryPath
            : sessionsDirectoryPath + "/"
        return standardizedPath.hasPrefix(directoryPrefix)
            && standardizedPath.hasSuffix(".jsonl")
    }
}

private enum LibProcError: Error {
    case callFailed(function: String, pid: Int32?, code: Int32)
    case malformedArguments(pid: Int32)
}

private struct LibProcProcessReader: DarwinProcessReading {
    func allPIDs() throws -> [Int32] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount >= 0 else {
            throw callError("proc_listallpids", pid: nil)
        }

        // Leave headroom for processes created after the size query.
        var pids = [Int32](repeating: 0, count: max(Int(estimatedCount) + 64, 64))
        let byteCapacity = pids.count * MemoryLayout<Int32>.stride
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(byteCapacity))
        }
        guard count >= 0 else {
            throw callError("proc_listallpids", pid: nil)
        }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    func bsdInfo(pid: Int32) throws -> DarwinBSDInfo {
        var info = proc_bsdinfo()
        let expectedSize = MemoryLayout<proc_bsdinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, Int32(expectedSize))
        }
        guard result == expectedSize else {
            throw callError("proc_pidinfo(PROC_PIDTBSDINFO)", pid: pid)
        }

        return DarwinBSDInfo(
            pid: Int32(info.pbi_pid),
            parentPID: Int32(info.pbi_ppid),
            userID: info.pbi_uid,
            startedAt: Date(
                timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                    + TimeInterval(info.pbi_start_tvusec) / 1_000_000
            ),
            hasControllingTerminal: (info.pbi_flags & UInt32(PROC_FLAG_CONTROLT)) != 0
        )
    }

    func executablePath(pid: Int32) throws -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_pidpath(pid, pointer.baseAddress, UInt32(pointer.count))
        }
        guard length > 0 else {
            throw callError("proc_pidpath", pid: pid)
        }
        return String(
            decoding: buffer.prefix(Int(length)).map(UInt8.init(bitPattern:)),
            as: UTF8.self
        )
    }

    func arguments(pid: Int32) throws -> [String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else {
            throw callError("sysctl(KERN_PROCARGS2 size)", pid: pid)
        }
        guard size >= MemoryLayout<Int32>.size else {
            throw LibProcError.malformedArguments(pid: pid)
        }

        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &bytes, &size, nil, 0) == 0 else {
            throw callError("sysctl(KERN_PROCARGS2)", pid: pid)
        }
        return try decodeArguments(bytes, pid: pid)
    }

    func workingDirectory(pid: Int32) throws -> String? {
        var info = proc_vnodepathinfo()
        let expectedSize = MemoryLayout<proc_vnodepathinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, pointer, Int32(expectedSize))
        }
        guard result == expectedSize else {
            throw callError("proc_pidinfo(PROC_PIDVNODEPATHINFO)", pid: pid)
        }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    func openFiles(pid: Int32) throws -> [DarwinOpenFile] {
        let byteCount = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard byteCount >= 0 else {
            throw callError("proc_pidinfo(PROC_PIDLISTFDS size)", pid: pid)
        }
        guard byteCount > 0 else { return [] }

        let descriptorSize = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](
            repeating: proc_fdinfo(),
            count: Int(byteCount) / descriptorSize + 16
        )
        let capacity = descriptors.count * descriptorSize
        let populatedBytes = descriptors.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(capacity))
        }
        guard populatedBytes >= 0 else {
            throw callError("proc_pidinfo(PROC_PIDLISTFDS)", pid: pid)
        }

        return descriptors.prefix(Int(populatedBytes) / descriptorSize).compactMap { descriptor in
            guard descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { return nil }
            return openFile(pid: pid, fileDescriptor: descriptor.proc_fd)
        }
    }

    private func openFile(pid: Int32, fileDescriptor: Int32) -> DarwinOpenFile? {
        var info = vnode_fdinfowithpath()
        let expectedSize = MemoryLayout<vnode_fdinfowithpath>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidfdinfo(
                pid,
                fileDescriptor,
                PROC_PIDFDVNODEPATHINFO,
                pointer,
                Int32(expectedSize)
            )
        }
        guard result == expectedSize else { return nil }

        let path = withUnsafePointer(to: &info.pvip.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        guard !path.isEmpty else { return nil }
        return DarwinOpenFile(path: path, openFlags: Int32(info.pfi.fi_openflags))
    }

    private func decodeArguments(_ bytes: [UInt8], pid: Int32) throws -> [String] {
        let argumentCount = bytes.withUnsafeBytes {
            $0.loadUnaligned(as: Int32.self)
        }
        guard argumentCount >= 0 else {
            throw LibProcError.malformedArguments(pid: pid)
        }

        var index = MemoryLayout<Int32>.size
        skipString(in: bytes, index: &index) // Executable path.
        skipNulls(in: bytes, index: &index)

        var result: [String] = []
        while result.count < Int(argumentCount), index < bytes.count {
            let start = index
            skipString(in: bytes, index: &index)
            guard index > start else { break }
            let value = String(decoding: bytes[start..<index], as: UTF8.self)
            result.append(value)
            skipNulls(in: bytes, index: &index)
        }
        return result
    }

    private func skipString(in bytes: [UInt8], index: inout Int) {
        while index < bytes.count, bytes[index] != 0 { index += 1 }
    }

    private func skipNulls(in bytes: [UInt8], index: inout Int) {
        while index < bytes.count, bytes[index] == 0 { index += 1 }
    }

    private func callError(_ function: String, pid: Int32?) -> LibProcError {
        LibProcError.callFailed(function: function, pid: pid, code: errno)
    }
}
