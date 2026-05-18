import Foundation

public enum ShareMountStatus: String, Codable, Equatable, Sendable {
    case mounted
    case notMounted
    case alreadyMounted
    case mountedNow
    case failed
}

public struct ShareStatus: Codable, Equatable, Sendable {
    public let name: String
    public let address: String
    public let mountPoint: String
    public let account: String
    public let pollIntervalSeconds: Int
    public let status: ShareMountStatus
    public let message: String?

    public init(config: SambaConfig, status: ShareMountStatus, message: String? = nil) {
        name = config.name
        address = config.address
        mountPoint = config.mountPoint
        account = config.account ?? "guest"
        pollIntervalSeconds = config.pollIntervalSeconds
        self.status = status
        self.message = message
    }
}

public protocol MountPointPreparing {
    func prepareMountPoint(_ path: String) throws
}

public final class FileManagerMountPointPreparer: MountPointPreparing {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func prepareMountPoint(_ path: String) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }

        do {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            if Self.shouldLetNetFSCreateVolumesMountPoint(path: path, error: error) {
                return
            }
            throw error
        }
    }

    static func shouldLetNetFSCreateVolumesMountPoint(path: String, error: Error) -> Bool {
        guard isDirectVolumesChild(path) else {
            return false
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileWriteNoPermission.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 13 {
            return true
        }
        return false
    }

    private static func isDirectVolumesChild(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        return components.count == 3 && components[0] == "/" && components[1] == "Volumes"
    }
}

public final class MountService {
    private let statusProvider: MountStatusProviding
    private let mounter: NetworkMounter
    private let credentials: CredentialStore
    private let mountPointPreparer: MountPointPreparing

    public init(
        statusProvider: MountStatusProviding,
        mounter: NetworkMounter,
        credentials: CredentialStore,
        fileManager: FileManager = .default
    ) {
        self.statusProvider = statusProvider
        self.mounter = mounter
        self.credentials = credentials
        self.mountPointPreparer = FileManagerMountPointPreparer(fileManager: fileManager)
    }

    public init(
        statusProvider: MountStatusProviding,
        mounter: NetworkMounter,
        credentials: CredentialStore,
        mountPointPreparer: MountPointPreparing
    ) {
        self.statusProvider = statusProvider
        self.mounter = mounter
        self.credentials = credentials
        self.mountPointPreparer = mountPointPreparer
    }

    public func statuses(for configs: [LoadedConfig]) -> [ShareStatus] {
        configs.map { loaded in
            ShareStatus(
                config: loaded.config,
                status: statusProvider.isMounted(at: loaded.config.mountPoint) ? .mounted : .notMounted
            )
        }
    }

    public func mountAll(_ configs: [LoadedConfig]) -> [ShareStatus] {
        configs.map { mount($0.config) }
    }

    @discardableResult
    public func mount(_ config: SambaConfig) -> ShareStatus {
        if statusProvider.isMounted(at: config.mountPoint) {
            return ShareStatus(config: config, status: .alreadyMounted)
        }

        do {
            try mountPointPreparer.prepareMountPoint(config.mountPoint)
            let remoteURL = try config.smbURL()
            let credential = try credential(for: config)
            try mounter.mount(MountRequest(remoteURL: remoteURL, mountPoint: config.mountPoint, credential: credential))
            return ShareStatus(config: config, status: .mountedNow)
        } catch {
            return ShareStatus(config: config, status: .failed, message: error.localizedDescription)
        }
    }

    private func credential(for config: SambaConfig) throws -> Credential? {
        guard let account = config.account, !account.isEmpty else {
            return nil
        }
        guard let password = try credentials.password(host: config.host, share: config.share, account: account) else {
            throw CredentialError.missing(host: config.host, share: config.share, account: account)
        }
        return Credential(account: account, password: password)
    }
}
