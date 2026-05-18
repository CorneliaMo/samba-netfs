import ArgumentParser
import Foundation
import MountSambaCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct MountSamba: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mount-samba",
        abstract: "Mount SMB/Samba shares using macOS NetFS.",
        subcommands: [
            Show.self,
            Mount.self,
            Run.self,
            Start.self,
            Stop.self,
            Status.self,
            SetCredential.self
        ],
        defaultSubcommand: Show.self
    )
}

struct ConfigOptions: ParsableArguments {
    @Option(name: .long, help: "Directory containing one JSON config file per Samba share.")
    var configDir: String?

    var directoryURL: URL {
        if let configDir {
            return URL(fileURLWithPath: configDir).standardizedFileURL
        }
        return ConfigPaths.defaultConfigDirectory()
    }
}

struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show configured shares and mount status.")

    @OptionGroup var options: ConfigOptions

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let configs = try ConfigLoader().load(from: options.directoryURL)
        let service = makeService()
        let statuses = service.statuses(for: configs)
        let output = try (json ? StatusFormatter.json(statuses) : StatusFormatter.table(statuses))
        print(output)
    }
}

struct Mount: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Mount all configured shares once.")

    @OptionGroup var options: ConfigOptions

    func run() throws {
        let configs = try ConfigLoader().load(from: options.directoryURL)
        let statuses = makeService().mountAll(configs)
        print(StatusFormatter.table(statuses))
        if statuses.contains(where: { $0.status == .failed }) {
            throw ExitCode.failure
        }
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run the foreground polling loop.")

    @OptionGroup var options: ConfigOptions

    mutating func run() throws {
        let configs = try ConfigLoader().load(from: options.directoryURL)
        RunSignal.install()
        PollingRunner(
            configs: configs,
            service: makeService(),
            shouldStop: { RunSignal.shouldStop }
        ).run()
    }
}

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start the polling loop as a background daemon.")

    @OptionGroup var options: ConfigOptions

    func run() throws {
        let controller = DaemonController()
        let pid = try controller.start(configDirectory: options.directoryURL)
        print("started mount-samba daemon with PID \(pid)")
        print("log: \(controller.logFile.path)")
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop the background daemon.")

    func run() throws {
        let state = try DaemonController().stop()
        switch state {
        case let .running(pid):
            print("sent SIGTERM to PID \(pid)")
        case let .stale(pid):
            print("removed stale PID file for PID \(pid)")
        case .stopped:
            print("daemon is not running")
        }
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show daemon status.")

    func run() throws {
        switch DaemonController().state() {
        case let .running(pid):
            print("running (PID \(pid))")
        case let .stale(pid):
            print("stale PID file (PID \(pid) is not running)")
        case .stopped:
            print("stopped")
        }
    }
}

struct SetCredential: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-credential",
        abstract: "Store or update a Keychain password for a configured share."
    )

    @Option(help: "Samba host.")
    var host: String

    @Option(help: "Samba share.")
    var share: String

    @Option(help: "Account name.")
    var account: String

    func run() throws {
        let password = try readPassword(prompt: "Password: ")
        try KeychainCredentialStore().setPassword(password, host: host, share: share, account: account)
        print("stored credential for \(account)@\(host)/\(share)")
    }
}

private func makeService() -> MountService {
    MountService(
        statusProvider: ShellMountStatusProvider(),
        mounter: NetFSNetworkMounter(),
        credentials: KeychainCredentialStore()
    )
}

private enum RunSignal {
    private static var stopFlag = false

    static var shouldStop: Bool {
        stopFlag
    }

    static func install() {
        signal(SIGTERM) { _ in RunSignal.stopFlag = true }
        signal(SIGINT) { _ in RunSignal.stopFlag = true }
    }
}

private func readPassword(prompt: String) throws -> String {
    FileHandle.standardError.write(Data(prompt.utf8))

    #if canImport(Darwin) || canImport(Glibc)
    var oldTerm = termios()
    guard tcgetattr(STDIN_FILENO, &oldTerm) == 0 else {
        throw RuntimeError("failed to read terminal settings")
    }
    var newTerm = oldTerm
    newTerm.c_lflag &= ~tcflag_t(ECHO)
    guard tcsetattr(STDIN_FILENO, TCSANOW, &newTerm) == 0 else {
        throw RuntimeError("failed to disable terminal echo")
    }
    defer {
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &oldTerm)
        FileHandle.standardError.write(Data("\n".utf8))
    }
    #endif

    guard let line = readLine(strippingNewline: true) else {
        throw RuntimeError("failed to read password")
    }
    return line
}

private struct RuntimeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
