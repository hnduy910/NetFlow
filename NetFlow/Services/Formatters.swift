import Foundation

enum ByteFormat {
    static func string(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .decimal)
    }
    static func rate(_ bytesPerSecond: Double) -> String {
        let bits = bytesPerSecond * 8
        if bits >= 1_000_000 { return String(format: "%.1f Mbps", bits / 1_000_000) }
        if bits >= 1_000 { return String(format: "%.0f Kbps", bits / 1_000) }
        return String(format: "%.0f bps", bits)
    }
}

extension DateFormatter {
    static let shortDay: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; return f }()
}
