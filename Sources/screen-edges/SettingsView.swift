import ScreenEdgesCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: StatusController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                groupHeader("Home Assistant")
                labeled("URL") {
                    TextField("http://192.168.2.5", text: $controller.config.haURL)
                        .textFieldStyle(.roundedBorder)
                }
                labeled("Access token") {
                    SecureField("Long-lived access token", text: $controller.config.haToken)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Only localtuya / zone lights", isOn: $controller.config.localtuyaOnly)
                HStack(alignment: .center, spacing: 12) {
                    Button("Connect & refresh lights") {
                        Task {
                            controller.save()
                            await controller.reconnect()
                        }
                    }
                    .disabled(controller.config.haToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text(controller.statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                groupHeader("Screen → light mapping")
                ForEach(EdgeName.allCases, id: \.rawValue) { edge in
                    labeled(edge.rawValue.capitalized) {
                        Picker("", selection: binding(for: edge)) {
                            Text("— not mapped —").tag("")
                            ForEach(controller.lights) { light in
                                Text("\(light.name)").tag(light.entityId)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("Map each edge to a Battletron zone light from localtuya.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                groupHeader("Capture")
                labeled("Interval (seconds)") {
                    TextField("0.15", value: $controller.config.interval, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                Toggle("Start sync when app launches", isOn: $controller.config.enabled)

                if let err = controller.lastError {
                    Text(err)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Save") {
                        controller.save()
                        Task { await controller.refreshLights() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 520)
        .onAppear {
            Task { await controller.refreshLights() }
        }
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
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
