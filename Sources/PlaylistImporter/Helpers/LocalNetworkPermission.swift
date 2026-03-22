import Foundation
import Network

/// Triggers the macOS Local Network permission dialog using a brief NWConnection attempt.
/// NWBrowser with Bonjour types is broken on macOS 26; a direct TCP probe works instead.
enum LocalNetworkPermission {

    static func requestIfNeeded(host: String, port: UInt16) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let state = _State(continuation: continuation)

            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!
            )
            let conn = NWConnection(to: endpoint, using: .tcp)

            conn.stateUpdateHandler = { newState in
                switch newState {
                case .ready, .failed, .cancelled:
                    state.finish(conn: conn)
                default:
                    break
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                state.finish(conn: conn)
            }

            conn.start(queue: .global())
        }
    }

    private final class _State: @unchecked Sendable {
        private let continuation: CheckedContinuation<Void, Never>
        private var finished = false
        private let lock = NSLock()

        init(continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func finish(conn: NWConnection) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            conn.cancel()
            continuation.resume()
        }
    }
}
