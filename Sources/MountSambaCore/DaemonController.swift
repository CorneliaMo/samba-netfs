import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum DaemonState: Equatable {
    case running(pid: Int32)
    case stale(pid: Int32)
    case stopped
}

public enum DaemonError: LocalizedError, Equatable {
    case unsupported
    case alreadyRunning(Int32)
    case missingExecutable

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "daemon mode is only available on macOS and Unix-like systems"
        case let .alreadyRunning(pid):
            return "daemon is already running with PID \(pid)"
        case .missingExecutable:
            return "cannot determine current executable path"
        }
    }
}

public final class DaemonController {
    public let directory: URL
    public let pidFile: URL
    public let logFile: URL

    private let fileManager: FileManager

    public init(directory: URL = ConfigPaths.daemonDirectory(), fileManager: FileManager = .default) {
        self.directory = directory
        self.pidFile = directory.appendingPathComponent("mount-samba.pid")
        self.logFile = directory.appendingPathComponent("mount-samba.log")
        self.fileManager = fileManager
    }

    public func state() -> DaemonState {
        guard let pid = readPID() else {
            return .stopped
        }
        return processExists(pid) ? .running(pid: pid) : .stale(pid: pid)
    }

    public func stop() throws -> DaemonState {
        let current = state()
        switch current {
        case let .running(pid):
            _ = kill(pid, SIGTERM)
            try? fileManager.removeItem(at: pidFile)
        case .stale:
            try? fileManager.removeItem(at: pidFile)
        case .stopped:
            break
        }
        return current
    }

    public func start(configDirectory: URL) throws -> Int32 {
        switch state() {
        case let .running(pid):
            throw DaemonError.alreadyRunning(pid)
        case .stale:
            try? fileManager.removeItem(at: pidFile)
        case .stopped:
            break
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let executable = Bundle.main.executablePath else {
            throw DaemonError.missingExecutable
        }

        if !fileManager.fileExists(atPath: logFile.path) {
            fileManager.createFile(atPath: logFile.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logFile)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["run", "--config-dir", configDirectory.path]
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()

        let pid = process.processIdentifier
        try "\(pid)\n".write(to: pidFile, atomically: true, encoding: .utf8)
        return pid
    }

    private func readPID() -> Int32? {
        guard let content = try? String(contentsOf: pidFile, encoding: .utf8) else {
            return nil
        }
        return Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func processExists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
