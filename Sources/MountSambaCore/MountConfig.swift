import Foundation

public enum ShareProtocol: String, Codable, CaseIterable, Sendable {
    case smb
    case nfs
    case http
    case https
}

public struct MountConfig: Codable, Equatable, Sendable {
    public let name: String
    public let mountProtocol: ShareProtocol
    public let host: String
    public let share: String
    public let path: String?
    public let pollIntervalSeconds: Int
    public let mountPoint: String
    public let account: String?

    public init(
        name: String,
        mountProtocol: ShareProtocol,
        host: String,
        share: String,
        path: String? = nil,
        pollIntervalSeconds: Int,
        mountPoint: String,
        account: String? = nil
    ) {
        self.name = name
        self.mountProtocol = mountProtocol
        self.host = host
        self.share = share
        self.path = path
        self.pollIntervalSeconds = pollIntervalSeconds
        self.mountPoint = mountPoint
        self.account = account
    }

    enum CodingKeys: String, CodingKey {
        case name
        case mountProtocol = "protocol"
        case host
        case share
        case path
        case pollIntervalSeconds
        case mountPoint
        case account
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        mountProtocol = try container.decode(ShareProtocol.self, forKey: .mountProtocol)
        host = try container.decode(String.self, forKey: .host)
        share = try container.decode(String.self, forKey: .share)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        pollIntervalSeconds = try container.decode(Int.self, forKey: .pollIntervalSeconds)
        mountPoint = try container.decode(String.self, forKey: .mountPoint)
        account = try container.decodeIfPresent(String.self, forKey: .account)
    }
}

public struct LoadedConfig: Equatable, Sendable {
    public let fileURL: URL
    public let config: MountConfig

    public init(fileURL: URL, config: MountConfig) {
        self.fileURL = fileURL
        self.config = config
    }
}

public enum ConfigError: LocalizedError, Equatable {
    case directoryMissing(String)
    case invalid(URL, String)
    case noConfigs(String)

    public var errorDescription: String? {
        switch self {
        case let .directoryMissing(path):
            return "config directory does not exist: \(path)"
        case let .invalid(url, reason):
            return "\(url.path): \(reason)"
        case let .noConfigs(path):
            return "no .json config files found in \(path)"
        }
    }
}

public enum ConfigPaths {
    public static func defaultConfigDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mount-samba-swift", isDirectory: true)
    }

    public static func daemonDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("mount-samba-swift", isDirectory: true)
    }
}

public final class ConfigLoader {
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default, decoder: JSONDecoder = JSONDecoder()) {
        self.fileManager = fileManager
        self.decoder = decoder
    }

    public func load(from directory: URL) throws -> [LoadedConfig] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ConfigError.directoryMissing(directory.path)
        }

        let files = try fileManager
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else {
            throw ConfigError.noConfigs(directory.path)
        }

        return try files.map { fileURL in
            do {
                let data = try Data(contentsOf: fileURL)
                let config = try decoder.decode(MountConfig.self, from: data)
                try config.validate(sourceURL: fileURL)
                _ = try config.remoteURL()
                return LoadedConfig(fileURL: fileURL, config: config)
            } catch let error as ConfigError {
                throw error
            } catch {
                throw ConfigError.invalid(fileURL, error.localizedDescription)
            }
        }
    }
}

public extension MountConfig {
    func validate(sourceURL: URL? = nil) throws {
        let errorURL = sourceURL ?? URL(fileURLWithPath: name.isEmpty ? "<config>" : name)
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigError.invalid(errorURL, "name must not be empty")
        }
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigError.invalid(errorURL, "host must not be empty")
        }
        if share.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigError.invalid(errorURL, "share must not be empty")
        }
        if mountPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigError.invalid(errorURL, "mountPoint must not be empty")
        }
        if pollIntervalSeconds <= 0 {
            throw ConfigError.invalid(errorURL, "pollIntervalSeconds must be positive")
        }
    }

    func remoteURL() throws -> URL {
        var components = URLComponents()
        components.scheme = mountProtocol.rawValue
        components.host = host

        var pathComponents = [share]
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pathComponents.append(contentsOf: path.split(separator: "/").map(String.init))
        }
        components.percentEncodedPath = "/" + pathComponents.map(Self.encodePathComponent).joined(separator: "/")

        guard let url = components.url else {
            throw ConfigError.invalid(URL(fileURLWithPath: name), "invalid URL")
        }
        return url
    }

    var address: String {
        var result = "\(mountProtocol.rawValue)://\(host)/\(share)"
        if let path, !path.isEmpty {
            result += "/\(path)"
        }
        return result
    }

    private static func encodePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
