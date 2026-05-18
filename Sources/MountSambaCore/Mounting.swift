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

    public var errorDescription: String? {
        switch self {
        case let .netFSFailed(message):
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
