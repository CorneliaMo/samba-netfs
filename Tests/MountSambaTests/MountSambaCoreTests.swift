import Foundation
@testable import MountSambaCore
import XCTest

final class MountSambaCoreTests: XCTestCase {
    func testDefaultConfigDirectory() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        XCTAssertEqual(
            ConfigPaths.defaultConfigDirectory(homeDirectory: home).path,
            "/Users/example/.config/mount-samba-swift"
        )
    }

    func testValidConfigDecodesAndBuildsSMBURL() throws {
        let config = SambaConfig(
            name: "Media NAS",
            host: "nas.local",
            share: "media share",
            path: "tv/season 1",
            pollIntervalSeconds: 60,
            mountPoint: "/Volumes/Media",
            account: "alice"
        )

        try config.validate()

        XCTAssertEqual(config.smbURL().absoluteString, "smb://nas.local/media%20share/tv/season%201")
        XCTAssertEqual(config.address, "nas.local/media share/tv/season 1")
    }

    func testInvalidConfigThrows() {
        let config = SambaConfig(
            name: "",
            host: "nas.local",
            share: "media",
            pollIntervalSeconds: -1,
            mountPoint: "/Volumes/Media"
        )

        XCTAssertThrowsError(try config.validate())
    }

    func testConfigLoaderLoadsJsonFilesOnly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = """
        {
          "name": "Media",
          "host": "nas.local",
          "share": "media",
          "pollIntervalSeconds": 30,
          "mountPoint": "\(directory.appendingPathComponent("Media").path)"
        }
        """
        try valid.write(to: directory.appendingPathComponent("media.json"), atomically: true, encoding: .utf8)
        try "ignored".write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        let loaded = try ConfigLoader().load(from: directory)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].config.name, "Media")
    }

    func testCredentialServiceKey() {
        XCTAssertEqual(
            CredentialKey.service(host: "nas.local", share: "media"),
            "mount-samba-swift:nas.local/media"
        )
    }

    func testMountServiceSkipsAlreadyMounted() {
        let config = sampleConfig(mountPoint: "/Volumes/Media")
        let mounter = FakeMounter()
        let service = MountService(
            statusProvider: FakeStatusProvider(mounted: ["/Volumes/Media"]),
            mounter: mounter,
            credentials: FakeCredentialStore()
        )

        let status = service.mount(config)

        XCTAssertEqual(status.status, .alreadyMounted)
        XCTAssertTrue(mounter.requests.isEmpty)
    }

    func testGuestMountPassesNoCredentials() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = sampleConfig(mountPoint: directory.appendingPathComponent("Media").path, account: nil)
        let mounter = FakeMounter()
        let service = MountService(
            statusProvider: FakeStatusProvider(),
            mounter: mounter,
            credentials: FakeCredentialStore()
        )

        let status = service.mount(config)

        XCTAssertEqual(status.status, .mountedNow)
        XCTAssertEqual(mounter.requests.count, 1)
        XCTAssertNil(mounter.requests[0].credential)
    }

    func testMissingCredentialFailsWithoutStoppingOtherMounts() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = LoadedConfig(
            fileURL: directory.appendingPathComponent("missing.json"),
            config: sampleConfig(
                name: "Missing",
                mountPoint: directory.appendingPathComponent("Missing").path,
                account: "alice"
            )
        )
        let guest = LoadedConfig(
            fileURL: directory.appendingPathComponent("guest.json"),
            config: sampleConfig(
                name: "Guest",
                mountPoint: directory.appendingPathComponent("Guest").path,
                account: nil
            )
        )

        let mounter = FakeMounter()
        let service = MountService(
            statusProvider: FakeStatusProvider(),
            mounter: mounter,
            credentials: FakeCredentialStore(passwords: [:])
        )

        let statuses = service.mountAll([missing, guest])

        XCTAssertEqual(statuses.map(\.status), [.failed, .mountedNow])
        XCTAssertEqual(mounter.requests.count, 1)
        XCTAssertNil(mounter.requests[0].credential)
    }

    func testShowStatusEncodesJson() throws {
        let status = ShareStatus(config: sampleConfig(), status: .mounted, message: nil)
        let json = try StatusFormatter.json([status])

        XCTAssertTrue(json.contains("\"name\" : \"Media\""))
        XCTAssertTrue(json.contains("\"status\" : \"mounted\""))
    }

    private func sampleConfig(
        name: String = "Media",
        mountPoint: String = "/Volumes/Media",
        account: String? = nil
    ) -> SambaConfig {
        SambaConfig(
            name: name,
            host: "nas.local",
            share: "media",
            pollIntervalSeconds: 60,
            mountPoint: mountPoint,
            account: account
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MountSambaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class FakeMounter: NetworkMounter {
    private(set) var requests: [MountRequest] = []
    var error: Error?

    func mount(_ request: MountRequest) throws {
        if let error {
            throw error
        }
        requests.append(request)
    }
}

private struct FakeStatusProvider: MountStatusProviding {
    var mounted: Set<String> = []

    func isMounted(at mountPoint: String) -> Bool {
        mounted.contains(mountPoint)
    }
}

private struct FakeCredentialStore: CredentialStore {
    var passwords: [String: String] = [:]

    func password(host: String, share: String, account: String) throws -> String? {
        passwords["\(host)/\(share)/\(account)"]
    }

    func setPassword(_ password: String, host: String, share: String, account: String) throws {}
}
