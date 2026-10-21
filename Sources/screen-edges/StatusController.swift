import AppKit
import ScreenEdgesCore
import SwiftUI

@MainActor
final class StatusController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let client = HomeAssistantClient()
    private var loopTask: Task<Void, Never>?
    private var lastSent: [EdgeName: RGB] = [:]

    @Published var config: AppConfig
    @Published var lights: [HALight] = []
    @Published var statusText = "Idle"
    @Published var lastError: String?

    override init() {
        if let loaded = try? AppConfig.load() {
            config = loaded
        } else {
            config = AppConfig()
        }
        super.init()
    }

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "light.max", accessibilityDescription: "Screen Edges")
            button.image?.isTemplate = true
        }
        rebuildMenu()
        fileLog("Screen Edges starting (HA REST → zone lights)")
        Task { await bootstrap() }
    }

    private func fileLog(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = AppConfig.defaultURL()
            .deletingLastPathComponent()
            .appendingPathComponent("screen-edges.log")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let sync = NSMenuItem(
            title: config.enabled ? "Pause screen sync" : "Start screen sync",
            action: #selector(toggleSync),
            keyEquivalent: ""
        )
        sync.target = self
        menu.addItem(sync)
        menu.addItem(NSMenuItem.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit Screen Edges", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func toggleSync() {
        config.enabled.toggle()
        save()
        rebuildMenu()
        Task {
            if config.enabled {
                await startLoop()
            } else {
                await stopLoop()
            }
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(controller: self)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Screen Edges"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 620, height: 580))
            window.minSize = NSSize(width: 520, height: 480)
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        Task {
            // If sync is enabled, LaunchAgent will restart us — do not turn the
            // strips off or a relaunch leaves everything dark until the next push.
            loopTask?.cancel()
            loopTask = nil
            if !config.enabled {
                for edge in EdgeName.allCases {
                    let id = config.edges.entity(for: edge)
                    if !id.isEmpty {
                        try? await client.turnOff(entityId: id)
                    }
                }
            }
            await client.disconnect()
            NSApp.terminate(nil)
        }
    }

    func save() {
        do {
            try config.save()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        rebuildMenu()
    }

    func bootstrap() async {
        let token = config.haToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusText = "Paste a HA access token, then Connect"
            fileLog("No HA token in config")
            return
        }
        statusText = "Connecting…"
        lastError = nil
        do {
            try await client.connect(urlString: config.haURL, token: token)
            lights = try await client.listLights(localtuyaOnly: config.localtuyaOnly)
            statusText = "Connected — \(lights.count) lights"
            lastError = nil
            fileLog("Connected to \(config.haURL) — \(lights.count) lights, enabled=\(config.enabled)")
            if config.enabled {
                await startLoop()
            }
        } catch {
            statusText = "Connection failed"
            lastError = error.localizedDescription
            lights = []
            fileLog("Connection failed: \(error.localizedDescription)")
        }
    }

    func reconnect() async {
        await client.disconnect()
        await bootstrap()
    }

    func refreshLights() async {
        let token = config.haToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            if await !client.isConnected {
                try await client.connect(urlString: config.haURL, token: token)
            }
            lights = try await client.listLights(localtuyaOnly: config.localtuyaOnly)
            statusText = "Connected — \(lights.count) lights"
            lastError = nil
        } catch {
            statusText = "Connection failed"
            lastError = error.localizedDescription
        }
    }

    private func startLoop() async {
        loopTask?.cancel()
        lastSent.removeAll()
        loopTask = Task { await runCaptureLoop() }
        statusText = "Syncing"
        fileLog("Sync loop started")
        rebuildMenu()
    }

    private func stopLoop() async {
        loopTask?.cancel()
        loopTask = nil
        statusText = "Paused"
        // Turn mapped lights off so strips do not stick on last colour.
        for edge in EdgeName.allCases {
            let id = config.edges.entity(for: edge)
            if !id.isEmpty {
                try? await client.turnOff(entityId: id)
            }
        }
        rebuildMenu()
    }

    private func runCaptureLoop() async {
        if !CGPreflightScreenCaptureAccess() {
            fileLog("Screen Recording permission missing — requesting")
            _ = CGRequestScreenCaptureAccess()
            if !CGPreflightScreenCaptureAccess() {
                statusText = "Allow Screen Recording"
                lastError = "System Settings → Privacy → Screen Recording → enable Screen Edges, then Start sync again"
                fileLog(lastError!)
            }
        }
        var pushes = 0
        while !Task.isCancelled {
            guard config.enabled else { break }
            do {
                if await !client.isConnected {
                    try await client.connect(urlString: config.haURL, token: config.haToken)
                }
                let frame = try await captureEdgeFrame()
                let colors = sampleEdges(frame.bytes, width: frame.width, height: frame.height)
                try await push(colors)
                pushes += 1
                if pushes == 1 || pushes % 40 == 0 {
                    fileLog(
                        "push #\(pushes) L=\(colors.left) T=\(colors.top) R=\(colors.right) B=\(colors.bottom)"
                    )
                }
                statusText = "Syncing"
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                statusText = "Error"
                fileLog("sync error: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            let interval = max(0.08, config.interval)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func push(_ colors: EdgeColors) async throws {
        // Monitor L/T/R already match the screen with direct mapping.
        let pairs: [(EdgeName, RGB)] = [
            (.left, colors.left),
            (.top, colors.top),
            (.right, colors.right),
            (.bottom, colors.bottom),
        ]
        // Serial updates — parallel turn_on races the localtuya zone painter.
        for (edge, rgb) in pairs {
            let entityId = config.edges.entity(for: edge)
            guard !entityId.isEmpty else { continue }
            if lastSent[edge] == rgb { continue }
            lastSent[edge] = rgb
            try await client.setLightRGB(entityId: entityId, rgb: rgb)
        }
    }
}
