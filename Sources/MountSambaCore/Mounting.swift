import CNetFS
import Foundation

public struct MountRequest: Equatable, Sendable {
    public let remoteURL: URL
    public let mountPoint: String
    public let credential: Credential?

    public init(remoteURL: URL, mountPoint: String, credential: Credential?) {
        self.remoteURL = remoteURL
        self.mountPoint = mountPoint
        self.credential = credential
    }
}

public protocol NetworkMounter {
    func mount(_ request: MountRequest) throws
}

public protocol MountStatusProviding {
    func isMounted(at mountPoint: String) -> Bool
}

public enum MountError: LocalizedError, Equatable {
    case netFSFailed(String)
    case finderFailed(String)
    case mountVerificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .netFSFailed(message):
            return message
        case let .finderFailed(message):
            return message
        case let .mountVerificationFailed(message):
            return message
        }
    }
}

public final class NetFSNetworkMounter: NetworkMounter {
    public init() {}

    public func mount(_ request: MountRequest) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = CNetFSMountURL(
            request.remoteURL.absoluteString,
            request.mountPoint,
            request.credential?.account,
            request.credential?.password,
            &errorPointer
        )
        defer {
            if let errorPointer {
                CNetFSFreeErrorMessage(errorPointer)
            }
        }
        guard status == 0 else {
            let message = errorPointer.map { String(cString: $0) } ?? "NetFS mount failed with status \(status)"
            throw MountError.netFSFailed(message)
        }
    }
}

public final class FinderNetworkMounter: NetworkMounter {
    private let executionTimeout: TimeInterval

    public init(executionTimeout: TimeInterval = 10) {
        self.executionTimeout = executionTimeout
    }

    public func mount(_ request: MountRequest) throws {
        let urlString = finderURLString(for: request)
        let script = """
        try
            tell application "Finder"
                with timeout of 2 seconds
                    mount volume "\(escapeAppleScriptString(urlString))"
                end timeout
            end tell
        on error errMsg
            error errMsg
        end try
        """

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let deadline = Date().addingTimeInterval(executionTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw MountError.finderFailed("Finder mount timed out")
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty
                ?? String(data: stdoutData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty
                ?? "Finder mount failed"
            throw MountError.finderFailed(message)
        }
    }

    private func finderURLString(for request: MountRequest) -> String {
        let path = request.remoteURL.path

        guard let credential = request.credential else {
            return "smb://\(request.remoteURL.host ?? "")\(path)"
        }

        let encodedUser = credential.account.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? credential.account
        let encodedPassword = credential.password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? credential.password
        return "smb://\(encodedUser):\(encodedPassword)@\(request.remoteURL.host ?? "")\(path)"
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

public final class ShellMountStatusProvider: MountStatusProviding {
    private let mountedPaths: () -> Set<String>

    public convenience init() {
        self.init {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/sbin/mount")
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            return Set(output.split(separator: "\n").compactMap { line in
                Self.parseMountPoint(from: String(line))
            })
        }
    }

    public init(mountedPaths: @escaping () -> Set<String>) {
        self.mountedPaths = mountedPaths
    }

    public func isMounted(at mountPoint: String) -> Bool {
        mountedPaths().contains(URL(fileURLWithPath: mountPoint).standardizedFileURL.path)
    }

    static func parseMountPoint(from line: String) -> String? {
        guard let range = line.range(of: " on ") else {
            return nil
        }
        let suffix = line[range.upperBound...]
        guard let typeRange = suffix.range(of: " (") else {
            return nil
        }
        return URL(fileURLWithPath: String(suffix[..<typeRange.lowerBound])).standardizedFileURL.path
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
