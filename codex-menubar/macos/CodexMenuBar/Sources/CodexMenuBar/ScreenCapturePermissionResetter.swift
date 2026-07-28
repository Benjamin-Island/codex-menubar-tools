import Foundation

struct ScreenCapturePermissionResetCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]

    static let codexMenuBar = Self(
        executableURL: URL(fileURLWithPath: "/usr/bin/tccutil"),
        arguments: [
            "reset",
            "ScreenCapture",
            "dev.benjamin.codex-menubar"
        ]
    )
}

enum ScreenCapturePermissionResetError: Error, Equatable, Sendable {
    case launchFailed
    case nonzeroExit(Int32)

    static func from(exitStatus: Int32) -> Self? {
        exitStatus == 0 ? nil : .nonzeroExit(exitStatus)
    }
}

protocol ScreenCapturePermissionResetting: Sendable {
    func reset() async -> Result<Void, ScreenCapturePermissionResetError>
}

actor SystemScreenCapturePermissionResetter:
    ScreenCapturePermissionResetting
{
    private let command: ScreenCapturePermissionResetCommand

    init(
        command: ScreenCapturePermissionResetCommand = .codexMenuBar
    ) {
        self.command = command
    }

    func reset()
        async -> Result<Void, ScreenCapturePermissionResetError>
    {
        let command = command
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = command.executableURL
            process.arguments = command.arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { completedProcess in
                if let error = ScreenCapturePermissionResetError.from(
                    exitStatus: completedProcess.terminationStatus
                ) {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(.launchFailed))
            }
        }
    }
}
