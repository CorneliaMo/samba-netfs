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
    case forkFailed
    case setsidFailed
    case missingExecutable

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "daemon mode is only available on macOS and Unix-like systems"
        case let .alreadyRunning(pid):
            return "daemon is already running with PID \(pid)"
        case .forkFailed:
            return "fork failed"
        case .setsidFailed:
            return "setsid failed"
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

        #if os(macOS) || os(Linux)
        let child = fork()
        if child < 0 {
            throw DaemonError.forkFailed
        }
        if child > 0 {
            try "\(child)\n".write(to: pidFile, atomically: true, encoding: .utf8)
            return child
        }

        if setsid() < 0 {
            exit(1)
        }

        freopen(logFile.path, "a", stdout)
        freopen(logFile.path, "a", stderr)

        guard let executable = Bundle.main.executablePath else {
            exit(1)
        }
        execl(executable, executable, "run", "--config-dir", configDirectory.path, nil)
        exit(1)
        #else
        throw DaemonError.unsupported
        #endif
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
