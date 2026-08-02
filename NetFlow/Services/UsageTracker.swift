import Foundation

final class UsageTracker {
    private let reader = NetworkInterfaceReader()
    private var previous: NetworkSnapshot?

    struct SampleResult {
        var snapshot: NetworkSnapshot
        var delta: NetworkDelta
        var rate: NetworkRate
    }

    func sample(previous external: NetworkSnapshot) -> SampleResult {
        let current = reader.read()
        let baseline = previous ?? (external.timestamp == .distantPast ? nil : external)
        defer { previous = current }
        guard let old = baseline else {
            return SampleResult(snapshot: current, delta: .zero, rate: .zero)
        }
        let seconds = max(current.timestamp.timeIntervalSince(old.timestamp), 0.001)
        guard current.wifi.received >= old.wifi.received,
              current.wifi.sent >= old.wifi.sent,
              current.cellular.received >= old.cellular.received,
              current.cellular.sent >= old.cellular.sent else {
            return SampleResult(snapshot: current, delta: .zero, rate: .zero)
        }
        let d = NetworkDelta(
            wifiReceived: current.wifi.received - old.wifi.received,
            wifiSent: current.wifi.sent - old.wifi.sent,
            cellularReceived: current.cellular.received - old.cellular.received,
            cellularSent: current.cellular.sent - old.cellular.sent,
            isValid: true
        )
        let r = NetworkRate(
            wifiDown: Double(d.wifiReceived) / seconds,
            wifiUp: Double(d.wifiSent) / seconds,
            cellularDown: Double(d.cellularReceived) / seconds,
            cellularUp: Double(d.cellularSent) / seconds
        )
        return SampleResult(snapshot: current, delta: d, rate: r)
    }

    func resetBaseline() { previous = nil }
}
