import Foundation
import Network

/// A bounded, authenticated subset of Hyperion's JSON LED-stream API.
public struct HyperionSession: Sendable {
    private let token: String
    public private(set) var authorized = false
    public private(set) var streaming = false

    public init(token: String) { self.token = token }

    public mutating func handle(_ data: Data) -> Data {
        guard data.count <= 65536,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return reply("unknown", success: false)
        }
        let command = body["command"] as? String ?? "unknown"
        let sub = body["subcommand"] as? String ?? ""
        let name = sub.isEmpty ? command : "\(command)-\(sub)"
        let tan = body["tan"] as? Int
        if command == "authorize", sub == "login" {
            authorized = !token.isEmpty && body["token"] as? String == token
            if !authorized { streaming = false }
            return reply(name, success: authorized, tan: tan)
        }
        guard authorized else { return reply(name, success: false, tan: tan) }
        switch name {
        case "ledcolors-ledstream-start": streaming = true
        case "ledcolors-ledstream-stop": streaming = false
        case "serverinfo":
            let leds = EdgeName.allCases.flatMap { edge in
                (0..<20).map { i -> [String: Any] in
                    let a = Double(i) / 20, b = Double(i + 1) / 20
                    switch edge {
                    case .left: return ["hmin": 0, "hmax": 0.08, "vmin": a, "vmax": b]
                    case .top: return ["hmin": a, "hmax": b, "vmin": 0, "vmax": 0.12]
                    case .right: return ["hmin": 0.92, "hmax": 1, "vmin": a, "vmax": b]
                    case .bottom: return ["hmin": a, "hmax": b, "vmin": 0.88, "vmax": 1]
                    }
                }
            }
            return reply(name, success: true, tan: tan, info: ["leds": leds])
        default: return reply(name, success: false, tan: tan)
        }
        return reply(name, success: true, tan: tan)
    }

    public func frame(_ colors: [RGB]) -> Data? {
        guard authorized, streaming, colors.count == 80 else { return nil }
        return try? JSONSerialization.data(withJSONObject: [
            "command": "ledcolors-ledstream-update",
            "data": ["leds": colors.map { [$0.r, $0.g, $0.b] }],
        ])
    }

    private func reply(_ command: String, success: Bool, tan: Int? = nil, info: [String: Any] = [:]) -> Data {
        var body: [String: Any] = ["command": command, "success": success, "info": info]
        if let tan { body["tan"] = tan }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}

/// All listener/client state stays on one queue; each client has at most one
/// frame in flight, so a slow subscriber cannot accumulate screen frames.
public final class HyperionServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "screen-edges.hyperion")
    private let token: String
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var colors: [RGB] = []

    // Listener callbacks run on the same serial queue as start/stop.
    private final class Startup: @unchecked Sendable { var completed = false }

    private final class Client: @unchecked Sendable {
        let connection: NWConnection
        var session: HyperionSession
        var sendingFrame = false
        init(_ connection: NWConnection, token: String) {
            self.connection = connection; session = HyperionSession(token: token)
        }
    }

    public init(token: String) { self.token = token }

    public func start(port: Int) async throws -> UInt16 {
        guard (0...65535).contains(port) else { throw HAClientError.unexpected("Invalid stream port") }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard listener == nil else { throw HAClientError.unexpected("Stream server already started") }
                    let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
                    let ws = NWProtocolWebSocket.Options()
                    ws.autoReplyPing = true
                    ws.maximumMessageSize = 65536
                    parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
                    let server = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: UInt16(port))!)
                    listener = server
                    let startup = Startup()
                    server.stateUpdateHandler = { [weak server] state in
                        guard let server else { return }
                        guard !startup.completed else { return }
                        switch state {
                        case .ready:
                            startup.completed = true
                            continuation.resume(returning: server.port!.rawValue)
                        case .failed(let error):
                            startup.completed = true
                            continuation.resume(throwing: error)
                        case .cancelled:
                            startup.completed = true
                            continuation.resume(throwing: CancellationError())
                        default: break
                        }
                    }
                    server.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    server.start(queue: queue)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func publish(_ colors: [RGB]) {
        guard colors.count == 80 else { return }
        queue.async { [self] in
            self.colors = colors
            for client in clients.values { sendFrame(client) }
        }
    }

    public func stop() {
        queue.async { [self] in
            listener?.cancel(); listener = nil
            for client in clients.values { client.connection.cancel() }
            clients.removeAll(); colors = []
        }
    }

    private func accept(_ connection: NWConnection) {
        guard clients.count < 4 else { connection.cancel(); return }
        let client = Client(connection, token: token)
        let id = ObjectIdentifier(connection)
        clients[id] = client
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.clients.removeValue(forKey: id)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(client)
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak client] in
            guard let client, !client.session.authorized else { return }
            client.connection.cancel(); self?.clients.removeValue(forKey: id)
        }
    }

    private func receive(_ client: Client) {
        client.connection.receiveMessage { [weak self] data, _, complete, error in
            guard let self else { return }
            guard error == nil, complete, let data, data.count <= 65536 else {
                client.connection.cancel(); return
            }
            let reply = client.session.handle(data)
            send(reply, client: client) { [weak self] in self?.sendFrame(client) }
            receive(client)
        }
    }

    private func sendFrame(_ client: Client) {
        guard !client.sendingFrame, let data = client.session.frame(colors) else { return }
        client.sendingFrame = true
        send(data, client: client) { client.sendingFrame = false }
    }

    private func send(_ data: Data, client: Client, completion: @escaping @Sendable () -> Void) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "json", metadata: [metadata])
        client.connection.send(content: data, contentContext: context, completion: .contentProcessed { error in
            if error != nil { client.connection.cancel() }
            completion()
        })
    }
}
