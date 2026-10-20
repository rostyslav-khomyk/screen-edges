import CoreGraphics
import Foundation
import Network
import ScreenCaptureKit
import ScreenEdgesCore

@main
struct ScreenEdgesMain {
    static func main() async {
        let configURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? defaultConfigPath())
        let config: DaemonConfig
        do {
            config = try DaemonConfig.load(from: configURL)
        } catch {
            fputs("Cannot read \(configURL.path): \(error)\n", stderr)
            exit(1)
        }
        let app = Daemon(config: config)
        do {
            try await app.run()
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }
}

private func defaultConfigPath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home
        .appendingPathComponent("Library/Application Support/ScreenEdges/config.json")
        .path
}

final class Daemon: @unchecked Sendable {
    let config: DaemonConfig
    private var colors = EdgeColors(left: RGB(0, 0, 0), top: RGB(0, 0, 0), right: RGB(0, 0, 0), bottom: RGB(0, 0, 0))
    private var sessions: [ObjectIdentifier: HyperionSession] = [:]
    private var sockets: [ObjectIdentifier: NWConnection] = [:]
    private var websocket: [ObjectIdentifier: Bool] = [:]
    private let lock = NSLock()

    init(config: DaemonConfig) {
        self.config = config
    }

    func run() async throws {
        let ws = try NWListener(using: websocketParameters(), on: NWEndpoint.Port(rawValue: config.websocketPort)!)
        let tcp = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: config.jsonPort)!)
        start(ws, websocket: true)
        start(tcp, websocket: false)
        fputs("Hyperion WebSocket \(config.websocketPort), JSON \(config.jsonPort)\n", stderr)
        try await captureLoop()
    }

    private func start(_ listener: NWListener, websocket: Bool) {
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, isWebSocket: websocket)
        }
        listener.start(queue: .main)
    }

    private func accept(_ connection: NWConnection, isWebSocket: Bool) {
        let session = HyperionSession(token: config.token)
        let id = ObjectIdentifier(connection)
        lock.lock()
        sessions[id] = session
        sockets[id] = connection
        websocket[id] = isWebSocket
        lock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.drop(connection) }
            if case .cancelled = state { self?.drop(connection) }
        }
        connection.start(queue: .main)
        if isWebSocket {
            receiveWebSocket(connection, session: session)
        } else {
            receiveTCP(connection, session: session, buffer: Data())
        }
    }

    private func drop(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        lock.lock()
        sessions[id] = nil
        sockets[id] = nil
        websocket[id] = nil
        lock.unlock()
    }

    private func receiveWebSocket(_ connection: NWConnection, session: HyperionSession) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data, let text = String(data: data, encoding: .utf8) {
                self?.reply(text, session: session, connection: connection, websocket: true)
            }
            if error == nil {
                self?.receiveWebSocket(connection, session: session)
            }
        }
    }

    private func receiveTCP(_ connection: NWConnection, session: HyperionSession, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var next = buffer
            if let data { next.append(data) }
            while let newline = next.firstIndex(of: 0x0A) {
                let line = next[next.startIndex..<newline]
                next.removeSubrange(next.startIndex...newline)
                if let text = String(data: line, encoding: .utf8) {
                    self?.reply(text, session: session, connection: connection, websocket: false)
                }
            }
            if error == nil && !isComplete {
                self?.receiveTCP(connection, session: session, buffer: next)
            }
        }
    }

    private func reply(_ text: String, session: HyperionSession, connection: NWConnection, websocket: Bool) {
        guard let reply = session.handle(text) else { return }
        send(reply.json + (websocket ? "" : "\n"), connection: connection, websocket: websocket)
    }

    private func send(_ text: String, connection: NWConnection, websocket: Bool) {
        if websocket {
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "text", metadata: [meta])
            connection.send(content: Data(text.utf8), contentContext: context, completion: .contentProcessed { _ in })
        } else {
            connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
        }
    }

    private func broadcast(_ colors: EdgeColors) {
        lock.lock()
        let pairs = sockets.map { ($0.key, $0.value, websocket[$0.key] ?? false) }
        lock.unlock()
        for (id, connection, isWebSocket) in pairs {
            lock.lock()
            let session = sessions[id]
            lock.unlock()
            guard let json = session?.streamUpdate(colors) else { continue }
            send(json + (isWebSocket ? "" : "\n"), connection: connection, websocket: isWebSocket)
        }
    }

    private func captureLoop() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.max(by: { $0.width < $1.width }) else {
            throw CaptureError.noDisplay
        }
        fputs("display \(display.width)x\(display.height)\n", stderr)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = 160
        streamConfig.height = max(1, Int((Double(display.height) / Double(display.width) * 160).rounded()))
        streamConfig.showsCursor = false
        streamConfig.queueDepth = 1
        let interval = max(0.05, config.interval)
        while true {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: streamConfig)
            let rgb = rgbBuffer(image)
            colors = sampleEdges(rgb.bytes, width: rgb.width, height: rgb.height)
            let snapshot = colors
            DispatchQueue.main.async { [weak self] in
                self?.broadcast(snapshot)
            }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}

private enum CaptureError: Error { case noDisplay }

private func websocketParameters() -> NWParameters {
    let ws = NWProtocolWebSocket.Options()
    ws.autoReplyPing = true
    let tcp = NWProtocolTCP.Options()
    let params = NWParameters(tls: nil, tcp: tcp)
    params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
    return params
}

private func rgbBuffer(_ image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var bgra = [UInt8](repeating: 0, count: bytesPerRow * height)
    bgra.withUnsafeMutableBytes { raw in
        if let ctx = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    var j = 0
    var i = 0
    while i + 2 < bgra.count && j + 2 < rgb.count {
        rgb[j] = bgra[i]
        rgb[j + 1] = bgra[i + 1]
        rgb[j + 2] = bgra[i + 2]
        j += 3
        i += 4
    }
    return (rgb, width, height)
}
