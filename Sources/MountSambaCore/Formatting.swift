import Foundation

public enum StatusFormatter {
    public static func table(_ statuses: [ShareStatus]) -> String {
        let headers = ["NAME", "ADDRESS", "MOUNT POINT", "ACCOUNT", "INTERVAL", "STATUS"]
        let rows = statuses.map {
            [
                $0.name,
                $0.address,
                $0.mountPoint,
                $0.account,
                "\($0.pollIntervalSeconds)s",
                $0.status.rawValue
            ]
        }
        let widths = (0..<headers.count).map { index in
            ([headers[index]] + rows.map { $0[index] }).map(\.count).max() ?? 0
        }

        func render(_ values: [String]) -> String {
            values.enumerated().map { index, value in
                value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }

        return ([render(headers)] + rows.map(render)).joined(separator: "\n")
    }

    public static func json(_ statuses: [ShareStatus]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(statuses)
        return String(decoding: data, as: UTF8.self)
    }
}
