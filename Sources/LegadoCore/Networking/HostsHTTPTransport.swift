import Foundation
import Network
import Security

public enum HostsHTTPTransport {
    public static func data(for request: URLRequest, address: String, ignoreCertificateErrors: Bool) async throws -> HTTPResponse {
        let operation = try HostsRequestOperation(request: request, address: address, ignoreCertificateErrors: ignoreCertificateErrors)
        return try await withTaskCancellationHandler {
            try await operation.run()
        } onCancel: { operation.cancel() }
    }
}

private final class HostsRequestOperation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "legado.hosts.\(UUID().uuidString)")
    private let connection: NWConnection
    private let request: URLRequest
    private var continuation: CheckedContinuation<HTTPResponse, Error>?
    private var buffer = Data()
    private var finished = false
    private var cancelled = false

    init(request: URLRequest, address: String, ignoreCertificateErrors: Bool) throws {
        guard let url = request.url, let host = url.host,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let port = NWEndpoint.Port(rawValue: UInt16(exactly: url.port ?? (url.scheme == "https" ? 443 : 80)) ?? 0),
              port.rawValue > 0 else { throw URLError(.badURL) }
        self.request = request
        let parameters: NWParameters
        if url.scheme?.lowercased() == "https" {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
            if ignoreCertificateErrors {
                sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
            }
            parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        } else { parameters = .tcp }
        connection = NWConnection(host: NWEndpoint.Host(address), port: port, using: parameters)
    }

    func run() async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                if self.cancelled { self.finish(.failure(CancellationError())); return }
                self.connection.stateUpdateHandler = { [weak self] state in
                    guard let self, !self.finished else { return }
                    switch state {
                    case .ready: self.send()
                    case .failed(let error): self.finish(.failure(error))
                    case .cancelled: self.finish(.failure(CancellationError()))
                    default: break
                    }
                }
                self.connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + max(1, self.request.timeoutInterval)) { [weak self] in
                    self?.finish(.failure(URLError(.timedOut)))
                }
            }
        }
    }

    func cancel() {
        queue.async {
            self.cancelled = true
            if self.continuation != nil { self.finish(.failure(CancellationError())) }
        }
    }

    private func send() {
        guard let url = request.url, let host = url.host,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            finish(.failure(URLError(.badURL))); return
        }
        let path = (parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath)
            + (parts.percentEncodedQuery.map { "?\($0)" } ?? "")
        var headers = request.allHTTPHeaderFields ?? [:]
        for name in headers.keys.filter({ ["host", "connection", "accept-encoding", "content-length", "transfer-encoding"].contains($0.lowercased()) }) {
            headers.removeValue(forKey: name)
        }
        let hostField = host.contains(":") ? "[\(host)]" : host
        headers["Host"] = hostField + (url.port.map { ":\($0)" } ?? "")
        headers["Connection"] = "close"
        headers["Accept-Encoding"] = "identity"
        let body = request.httpBody ?? Data()
        if !body.isEmpty || request.httpMethod == "POST" || request.httpMethod == "PUT" {
            headers["Content-Length"] = String(body.count)
        }
        if request.httpShouldHandleCookies, headers.keys.contains(where: { $0.lowercased() == "cookie" }) == false {
            headers.merge(HTTPCookie.requestHeaderFields(with: HTTPCookieStorage.shared.cookies(for: url) ?? [])) { explicit, _ in explicit }
        }
        let method = request.httpMethod ?? "GET"
        guard !method.contains(where: { $0.isWhitespace }), !path.contains(where: { $0.isNewline }),
              headers.allSatisfy({ !$0.key.contains(where: { $0.isNewline }) && !$0.value.contains(where: { $0.isNewline }) }) else {
            finish(.failure(URLError(.badURL))); return
        }
        let head = "\(method) \(path) HTTP/1.1\r\n"
            + headers.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.finish(.failure(error)) } else { self?.receive() }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, !self.finished else { return }
            if let error { self.finish(.failure(error)); return }
            if let data { self.buffer.append(data) }
            do {
                if let response = try HostsHTTPResponseDecoder.decode(self.buffer, url: self.request.url!, method: self.request.httpMethod ?? "GET", complete: complete) {
                    if self.request.httpShouldHandleCookies {
                        let cookies = HTTPCookie.cookies(withResponseHeaderFields: response.headers, for: response.finalURL)
                        cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
                    }
                    self.finish(.success(response))
                } else if complete { self.finish(.failure(URLError(.badServerResponse))) }
                else { self.receive() }
            } catch { self.finish(.failure(error)) }
        }
    }

    private func finish(_ result: Result<HTTPResponse, Error>) {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}

public enum HostsHTTPResponseDecoder {
    public static func decode(_ data: Data, url: URL, method: String = "GET", complete: Bool = false) throws -> HTTPResponse? {
        guard data.count <= 64 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > 64 * 1024 { throw URLError(.badServerResponse) }
            return nil
        }
        guard boundary.lowerBound <= 64 * 1024 else { throw URLError(.badServerResponse) }
        let lines = String(decoding: data[..<boundary.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        guard let statusLine = lines.first, statusLine.hasPrefix("HTTP/1."),
              let status = Int(statusLine.split(separator: " ").dropFirst().first ?? "") else { throw URLError(.badServerResponse) }
        let remaining = Data(data[boundary.upperBound...])
        if (100...199).contains(status) && status != 101 {
            return try decode(remaining, url: url, method: method, complete: complete)
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw URLError(.badServerResponse) }
            let name = String(line[..<colon]).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }
        let body: Data
        if method == "HEAD" || status == 204 || status == 304 { body = Data() }
        else if headers["transfer-encoding"]?.lowercased() == "chunked" {
            guard let decoded = try decodeChunks(remaining) else { return nil }
            body = decoded
        } else if let rawLength = headers["content-length"] {
            guard let length = Int(rawLength), length >= 0, length <= 64 * 1024 * 1024 else { throw URLError(.badServerResponse) }
            guard remaining.count >= length else { return nil }
            body = Data(remaining.prefix(length))
        } else {
            guard complete else { return nil }
            body = remaining
        }
        guard headers["content-encoding"] == nil || headers["content-encoding"] == "identity" || body.isEmpty else {
            throw SettingsError.invalid("Hosts 请求收到不支持的压缩响应，请移除此域名的 Hosts 覆盖后重试。")
        }
        return .init(data: body, statusCode: status, headers: headers, finalURL: url)
    }

    private static func decodeChunks(_ data: Data) throws -> Data? {
        var offset = data.startIndex
        var body = Data()
        let newline = Data("\r\n".utf8)
        while offset < data.endIndex {
            guard let line = data.range(of: newline, in: offset..<data.endIndex) else { return nil }
            let value = String(decoding: data[offset..<line.lowerBound], as: UTF8.self).components(separatedBy: ";")[0]
            guard let count = Int(value.trimmingCharacters(in: .whitespaces), radix: 16), count >= 0,
                  count <= 64 * 1024 * 1024 else { throw URLError(.badServerResponse) }
            offset = line.upperBound
            if count == 0 {
                if data[offset...].starts(with: newline) || data.range(of: Data("\r\n\r\n".utf8), in: offset..<data.endIndex) != nil { return body }
                return nil
            }
            guard data.endIndex - offset >= count + 2 else { return nil }
            body.append(data[offset..<(offset + count)])
            offset += count
            guard data[offset..<(offset + 2)] == newline else { throw URLError(.badServerResponse) }
            offset += 2
        }
        return nil
    }
}
