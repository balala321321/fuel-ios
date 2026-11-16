import Foundation
import Network

final class LocalServer {
    private let root: URL
    private let queue = DispatchQueue(label: "fuel.local.server")
    private var listener: NWListener?
    var onReady: ((UInt16) -> Void)?

    /// 固定端口：origin 保持不变，WKWebView 的 localStorage 才能跨启动沿用
    static let fixedPort: UInt16 = 47821

    init(root: URL) {
        self.root = root
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: LocalServer.fixedPort) else {
                startRandom()
                return
            }
            let l = try NWListener(using: params, on: port)
            listener = l
            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    let p = self.listener?.port?.rawValue ?? LocalServer.fixedPort
                    DispatchQueue.main.async { self.onReady?(p) }
                case .failed, .cancelled:
                    self.startRandom()
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.start(queue: queue)
        } catch {
            startRandom()
        }
    }

    private func startRandom() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            listener = l
            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                if case .ready = state, let port = self.listener?.port?.rawValue {
                    DispatchQueue.main.async { self.onReady?(port) }
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.start(queue: queue)
        } catch {
            DispatchQueue.main.async { self.onReady?(0) }
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self = self else { conn.cancel(); return }
            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            let firstLine = text.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.components(separatedBy: " ")
            var path = parts.count > 1 ? parts[1] : "/"
            if let q = path.firstIndex(of: "?") { path = String(path[path.startIndex..<q]) }
            if path == "/" { path = "/index.html" }
            let name = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let fileURL = self.root.appendingPathComponent(name)
            var body = Data("not found".utf8)
            var status = "404 Not Found"
            if let d = try? Data(contentsOf: fileURL) {
                body = d
                status = "200 OK"
            }
            var mime = "application/octet-stream"
            if name.hasSuffix(".html") { mime = "text/html; charset=utf-8" }
            else if name.hasSuffix(".js") { mime = "application/javascript; charset=utf-8" }
            else if name.hasSuffix(".css") { mime = "text/css; charset=utf-8" }
            else if name.hasSuffix(".png") { mime = "image/png" }
            let head = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            let resp = Data(head.utf8) + body
            conn.send(content: resp, isComplete: true, completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }
}
