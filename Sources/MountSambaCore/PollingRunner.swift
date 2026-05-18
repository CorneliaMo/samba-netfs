import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class PollingRunner {
    private let configs: [LoadedConfig]
    private let service: MountService
    private let logger: (String) -> Void
    private let shouldStop: () -> Bool
    private let sleepSeconds: UInt32

    public init(
        configs: [LoadedConfig],
        service: MountService,
        logger: @escaping (String) -> Void = { print($0) },
        shouldStop: @escaping () -> Bool = { false },
        sleepSeconds: UInt32 = 1
    ) {
        self.configs = configs
        self.service = service
        self.logger = logger
        self.shouldStop = shouldStop
        self.sleepSeconds = sleepSeconds
    }

    public func run() {
        var nextRun = Dictionary(uniqueKeysWithValues: configs.map { ($0.fileURL.path, Date.distantPast) })

        while !shouldStop() {
            let now = Date()
            for loaded in configs {
                let key = loaded.fileURL.path
                guard now >= (nextRun[key] ?? .distantPast) else {
                    continue
                }
                let result = service.mount(loaded.config)
                log(result)
                nextRun[key] = now.addingTimeInterval(TimeInterval(loaded.config.pollIntervalSeconds))
            }
            sleep(sleepSeconds)
        }
    }

    private func log(_ status: ShareStatus) {
        var line = "[\(Date())] \(status.name) \(status.address) -> \(status.status.rawValue)"
        if let message = status.message {
            line += ": \(message)"
        }
        logger(line)
    }
}
