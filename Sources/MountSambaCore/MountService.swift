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

public final class MountService {
    private let statusProvider: MountStatusProviding
    private let mounter: NetworkMounter
    private let credentials: CredentialStore
    private let fileManager: FileManager

    public init(
        statusProvider: MountStatusProviding,
        mounter: NetworkMounter,
        credentials: CredentialStore,
        fileManager: FileManager = .default
    ) {
        self.statusProvider = statusProvider
        self.mounter = mounter
        self.credentials = credentials
        self.fileManager = fileManager
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
            try ensureMountPoint(config.mountPoint)
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

    private func ensureMountPoint(_ path: String) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
}
