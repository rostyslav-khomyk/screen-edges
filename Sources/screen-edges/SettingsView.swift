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
                HStack(alignment: .center, spacing: 12) {
                    Button("Connect & refresh zones") {
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

                groupHeader("Screen → strip zones")
                ForEach(controller.zones) { zone in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(zone.deviceName) — \(zone.name)")
                            .font(.subheadline)
                        HStack {
                            Text("\(zone.cm) cm · \(zone.sections) sections")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Picker("Screen edge", selection: binding(for: zone.entityId)) {
                                Text("Not mapped").tag("")
                                ForEach(EdgeName.allCases, id: \.rawValue) { edge in
                                    Text(edge.rawValue.capitalized).tag(edge.rawValue)
                                }
                            }.labelsHidden().frame(width: 140)
                            Toggle("Reverse", isOn: reverseBinding(for: zone.entityId))
                                .disabled(!controller.config.mappings.contains { $0.entityId == zone.entityId })
                        }
                    }
                }
                Text("An edge can feed multiple zones. Sync owns each selected strip; pause restores its saved lights. Reverse changes the color direction along a zone.")
                    .font(.caption).foregroundStyle(.secondary)
                let missing = controller.config.mappings.filter { mapping in
                    !controller.zones.contains { $0.entityId == mapping.entityId }
                }
                ForEach(missing) { mapping in
                    HStack {
                        Text("Unavailable zone: \(mapping.entityId)").foregroundStyle(.red)
                        Button("Remove mapping") {
                            controller.config.mappings.removeAll { $0.entityId == mapping.entityId }
                        }
                    }
                }

                Divider()

                groupHeader("Capture")
                labeled("Interval (seconds)") {
                    TextField("0.15", value: $controller.config.interval, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                labeled("Streaming port") {
                    TextField("8090", value: $controller.config.streamPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 100)
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
                        Task { await controller.reconnect() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 520)
        .onAppear {
            Task { await controller.refreshZones() }
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

    private func binding(for entityId: String) -> Binding<String> {
        Binding(
            get: { controller.config.mappings.first { $0.entityId == entityId }?.edge.rawValue ?? "" },
            set: { value in
                let reverse = controller.config.mappings.first { $0.entityId == entityId }?.reverse ?? false
                controller.config.mappings.removeAll { $0.entityId == entityId }
                if let edge = EdgeName(rawValue: value) {
                    controller.config.mappings.append(ZoneMapping(entityId: entityId, edge: edge, reverse: reverse))
                }
            }
        )
    }

    private func reverseBinding(for entityId: String) -> Binding<Bool> {
        Binding(
            get: { controller.config.mappings.first { $0.entityId == entityId }?.reverse ?? false },
            set: { value in
                if let index = controller.config.mappings.firstIndex(where: { $0.entityId == entityId }) {
                    controller.config.mappings[index].reverse = value
                }
            }
        )
    }
}
