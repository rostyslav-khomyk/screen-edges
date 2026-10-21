import ScreenEdgesCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: StatusController

    var body: some View {
        Form {
            Section("Home Assistant") {
                TextField("URL", text: $controller.config.haURL)
                SecureField("Long-lived access token", text: $controller.config.haToken)
                Toggle("Only localtuya lights", isOn: $controller.config.localtuyaOnly)
                HStack {
                    Button("Connect & refresh lights") {
                        Task {
                            controller.save()
                            await controller.reconnect()
                        }
                    }
                    Text(controller.statusText).foregroundStyle(.secondary)
                }
            }

            Section("Screen → light mapping") {
                ForEach(EdgeName.allCases, id: \.rawValue) { edge in
                    Picker(edge.rawValue.capitalized, selection: binding(for: edge)) {
                        Text("— not mapped —").tag("")
                        ForEach(controller.lights) { light in
                            Text("\(light.name) (\(light.entityId))").tag(light.entityId)
                        }
                    }
                }
                Text("Map each edge to a Battletron zone light from localtuya.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture") {
                HStack {
                    Text("Interval (seconds)")
                    TextField("", value: $controller.config.interval, format: .number)
                        .frame(width: 60)
                }
                Toggle("Start sync when app launches", isOn: $controller.config.enabled)
            }

            if let err = controller.lastError {
                Section {
                    Text(err).foregroundStyle(.red)
                }
            }

            Section {
                Button("Save") {
                    controller.save()
                    Task { await controller.refreshLights() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            Task { await controller.refreshLights() }
        }
    }

    private func binding(for edge: EdgeName) -> Binding<String> {
        Binding(
            get: { controller.config.edges.entity(for: edge) },
            set: { value in
                controller.config.edges.set(edge, entityId: value)
            }
        )
    }
}
