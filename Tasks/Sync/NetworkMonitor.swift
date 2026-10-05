import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline: Bool
    var onChange: (() -> Void)?

    private var pathIsSatisfied: Bool
    private let monitor: NWPathMonitor?

    #if DEBUG
    var debugForceOffline: Bool = false {
        didSet { recompute() }
    }
    #endif

    init(startMonitoring: Bool = true) {
        pathIsSatisfied = true
        isOnline = true
        guard startMonitoring else {
            monitor = nil
            return
        }

        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.setOnline(satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    func setOnline(_ value: Bool) {
        pathIsSatisfied = value
        recompute()
    }

    private func recompute() {
        var effective = pathIsSatisfied
        #if DEBUG
        if debugForceOffline { effective = false }
        #endif
        guard effective != isOnline else { return }
        isOnline = effective
        onChange?()
    }

    deinit {
        monitor?.cancel()
    }
}
