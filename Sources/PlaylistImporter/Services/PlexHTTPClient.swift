import Foundation
import Network

/// HTTP client that bypasses VPN tunnels (e.g. Cloudflare Warp) by prohibiting
/// interfaces of type `.other` — which is how macOS classifies utun/VPN interfaces.
/// This forces NWConnection to use only physical WiFi or Ethernet.
actor PlexHTTPClient {

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await Self.perform(request: request)
    }

    // MARK: - HTTP Request

    private static func perform(request: URLRequest) async throws -> (Data, URLResponse) {
        return try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await connect(request: request) }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func connect(request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, let host = url.host, let rawPort = url.port else {
            throw URLError(.badURL)
        }

        let params = NWParameters.tcp
        params.serviceClass = .responsiveData
        // VPN tunnels (Warp, WireGuard, etc.) appear as .other on macOS.
        // Prohibiting them forces NWConnection onto physical WiFi/Ethernet only.
        params.prohibitedInterfaceTypes = [.other, .cellular, .loopback]

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(rawPort))!
        )

        return try await withCheckedThrowingContinuation { continuation in
            let conn = NWConnection(to: endpoint, using: params)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let httpBytes = buildHTTPRequest(request)
                    conn.send(content: httpBytes, completion: .contentProcessed { error in
                        if let error = error {
                            conn.cancel()
                            continuation.resume(throwing: error)
                            return
                        }
                        readResponse(conn: conn, accumulated: Data()) { rawData in
                            conn.cancel()
                            do {
                                let result = try parseResponse(rawData, url: url)
                                continuation.resume(returning: result)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    })
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    break
                default:
                    break
                }
            }

            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    // MARK: - Request Builder

    private static func buildHTTPRequest(_ request: URLRequest) -> Data {
        guard let url = request.url else { return Data() }
        let method = request.httpMethod ?? "GET"
        let path = url.pathWithQuery
        let host = url.host ?? ""
        let portStr = url.port.map { ":\($0)" } ?? ""

        var lines = "\(method) \(path) HTTP/1.1\r\n"
        lines += "Host: \(host)\(portStr)\r\n"
        lines += "Connection: close\r\n"

        request.allHTTPHeaderFields?.forEach { key, value in
            let lower = key.lowercased()
            guard lower != "host", lower != "connection" else { return }
            lines += "\(key): \(value)\r\n"
        }
        lines += "\r\n"

        var data = lines.data(using: .utf8) ?? Data()
        if let body = request.httpBody { data.append(body) }
        return data
    }

    // MARK: - Response Reader (Content-Length aware)

    private static func readResponse(
        conn: NWConnection,
        accumulated: Data,
        completion: @escaping @Sendable (Data) -> Void
    ) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { chunk, _, isComplete, _ in
            var buf = accumulated
            if let chunk { buf.append(chunk) }

            let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])
            if let headerRange = buf.range(of: sep) {
                let headerStr = String(data: buf[buf.startIndex..<headerRange.lowerBound], encoding: .utf8) ?? ""
                let headerLines = headerStr.lowercased().components(separatedBy: "\r\n")
                let bodyStart = buf.distance(from: buf.startIndex, to: headerRange.upperBound)
                let bodyReceived = buf.count - bodyStart

                if let clLine = headerLines.first(where: { $0.hasPrefix("content-length:") }) {
                    let clStr = clLine.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                    if let contentLength = Int(clStr), bodyReceived >= contentLength {
                        completion(buf)
                        return
                    }
                }

                let isChunked = headerLines.contains { $0.contains("transfer-encoding") && $0.contains("chunked") }
                if isChunked, buf.range(of: Data("0\r\n\r\n".utf8)) != nil {
                    completion(buf)
                    return
                }
            }

            if isComplete || chunk == nil {
                completion(buf)
            } else {
                readResponse(conn: conn, accumulated: buf, completion: completion)
            }
        }
    }

    // MARK: - Response Parser

    private static func parseResponse(_ raw: Data, url: URL) throws -> (Data, URLResponse) {
        let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let headerRange = raw.range(of: sep) else { throw URLError(.badServerResponse) }

        let headerStr = String(data: raw[raw.startIndex..<headerRange.lowerBound], encoding: .utf8) ?? ""
        let lines = headerStr.components(separatedBy: "\r\n")

        guard let statusLine = lines.first else { throw URLError(.badServerResponse) }
        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let statusCode = Int(parts[1]) else { throw URLError(.badServerResponse) }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = val
        }

        var body = Data(raw[headerRange.upperBound...])
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            body = dechunk(body)
        }

        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, response)
    }

    // MARK: - Dechunk

    private static func dechunk(_ data: Data) -> Data {
        var result = Data()
        var i = data.startIndex
        let crlf = Data([0x0D, 0x0A])
        while i < data.endIndex {
            guard let lineEnd = data[i...].range(of: crlf) else { break }
            let sizeHex = String(data: data[i..<lineEnd.lowerBound], encoding: .utf8) ?? "0"
            let chunkSize = Int(sizeHex.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) ?? 0
            guard chunkSize > 0 else { break }
            let dataStart = lineEnd.upperBound
            guard let dataEnd = data.index(dataStart, offsetBy: chunkSize, limitedBy: data.endIndex) else { break }
            result.append(data[dataStart..<dataEnd])
            guard let next = data.index(dataEnd, offsetBy: 2, limitedBy: data.endIndex) else { break }
            i = next
        }
        return result
    }
}

// MARK: - URL Helper

private extension URL {
    var pathWithQuery: String {
        var s = path.isEmpty ? "/" : path
        if let q = query { s += "?\(q)" }
        return s
    }
}
