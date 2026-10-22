import AppKit
import ScreenEdgesCore
import SwiftUI

@MainActor
final class StatusController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let client = HomeAssistantClient()
    private var loopTask: Task<Void, Never>?
    private var generation = 0

    @Published var config: AppConfig
    @Published var zones: [HASyncZone] = []
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
        save()
        fileLog("Screen Edges starting (Hyperion granular stream → HA)")
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
            await stopLoop()
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
            zones = try await client.syncLayout().zones
            statusText = "Connected — \(zones.count) zones"
            lastError = nil
            fileLog("Connected to \(config.haURL) — \(zones.count) zones, enabled=\(config.enabled)")
            if config.enabled {
                await startLoop()
            }
        } catch {
            statusText = "Connection failed"
            lastError = error.localizedDescription
            zones = []
            fileLog("Connection failed: \(error.localizedDescription)")
            if config.enabled { await startLoop() }
        }
    }

    func reconnect() async {
        await stopLoop()
        await client.disconnect()
        await bootstrap()
    }

    func refreshZones() async {
        let token = config.haToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            if await !client.isConnected {
                try await client.connect(urlString: config.haURL, token: token)
            }
            zones = try await client.syncLayout().zones
            statusText = "Connected — \(zones.count) zones"
            lastError = nil
        } catch {
            statusText = "Connection failed"
            lastError = error.localizedDescription
        }
    }

    private func startLoop() async {
        generation += 1
        let current = generation
        let previous = loopTask
        previous?.cancel()
        let settings = config
        loopTask = Task {
            await previous?.value
            guard !Task.isCancelled, generation == current, settings.enabled else { return }
            await runCaptureLoop(settings)
        }
        statusText = "Starting sync…"
        rebuildMenu()
    }

    private func stopLoop() async {
        generation += 1
        let current = generation
        let previous = loopTask
        previous?.cancel()
        await previous?.value
        guard generation == current else { return }
        loopTask = nil
        statusText = "Paused"
        rebuildMenu()
    }

    private func runCaptureLoop(_ settings: AppConfig) async {
        guard !settings.mappings.isEmpty else {
            statusText = "Choose at least one zone"
            return
        }
        guard Set(settings.mappings.map(\.entityId)).count == settings.mappings.count,
              settings.interval.isFinite, settings.interval > 0,
              (1024...65535).contains(settings.streamPort) else {
            statusText = "Invalid sync settings"
            return
        }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            guard CGPreflightScreenCaptureAccess() else {
                statusText = "Allow Screen Recording"
                lastError = "Enable Screen Edges in System Settings → Privacy → Screen Recording"
                return
            }
        }
        let server = HyperionServer(token: settings.streamToken)
        do {
            let port = try await server.start(port: settings.streamPort)
            var nextCheck = Date.distantPast
            var claimed = false
            var needsClaim = true
            var outputEnabled = true
            var loggedError: String?
            while !Task.isCancelled {
                do {
                    if Date() >= nextCheck {
                        let layout = try await client.syncLayout()
                        zones = layout.zones
                        outputEnabled = layout.outputEnabled(for: settings.mappings)
                        needsClaim = !claimed || !layout.owners.contains(settings.ownerID)
                        nextCheck = Date().addingTimeInterval(2)
                    }
                    if !outputEnabled {
                        claimed = false
                        if statusText != "Suspended by Home Assistant" {
                            fileLog("Suspended by Home Assistant")
                        }
                        statusText = "Suspended by Home Assistant"
                        lastError = nil
                        try await Task.sleep(for: .seconds(2))
                        continue
                    }
                    let frame = try await captureEdgeFrame()
                    try Task.checkCancellation()
                    server.publish(sampleGranularEdges(frame.bytes, width: frame.width, height: frame.height))
                    if needsClaim {
                        try await client.startStream(config: settings, port: port)
                        claimed = true
                        needsClaim = false
                        fileLog("Granular sync acquired (\(settings.mappings.count) zones)")
                    }
                    statusText = "Syncing — granular colors"
                    lastError = nil
                    loggedError = nil
                    try await Task.sleep(for: .seconds(max(0.1, min(settings.interval, 2))))
                } catch {
                    if Task.isCancelled { break }
                    statusText = "Reconnecting…"
                    lastError = error.localizedDescription
                    if loggedError != lastError {
                        fileLog("Sync error: \(error.localizedDescription)")
                        loggedError = lastError
                    }
                    claimed = false
                    needsClaim = true
                    nextCheck = .distantPast
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        } catch {
            statusText = "Stream server failed"
            lastError = error.localizedDescription
            fileLog("Stream server failed: \(error.localizedDescription)")
        }
        server.stop()
        try? await client.stopStream(owner: settings.ownerID)
        fileLog("Granular sync released")
    }
}
