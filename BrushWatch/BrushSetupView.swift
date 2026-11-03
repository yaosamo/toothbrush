import SwiftUI
import CoreBluetooth

struct BrushSetupView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: AchievementStore

    var body: some View {
        NavigationStack {
            List {
                Section { StatusCard() }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                if ble.bluetoothState != .poweredOn {
                    Section {
                        Label(bluetoothMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if case .unsupported(let why) = ble.link {
                    Section { Label(why, systemImage: "xmark.octagon").foregroundStyle(.red) }
                }

                if ble.brushID != nil {
                    Section("Brush") {
                        LabeledContent("Connection", value: linkText)
                        LabeledContent("Handle state", value: ble.handleStateText)
                        LabeledContent("Brushing state", value: ble.brushingStateText)
                        LabeledContent("Brushing time", value: ble.brushingTime.map(format) ?? "—")
                        LabeledContent("Battery", value: ble.battery.map { "\($0)%" } ?? "—")
                    }
                }

                Section {
                    Toggle("Simulate brushing", isOn: Binding(get: { ble.simulating }, set: { ble.simulate($0) }))
                    Button("Reset achievements", role: .destructive) { store.reset() }
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Simulation drives the panda exactly like a real brush. Sessions under \(store.minimumSeconds)s don't count.")
                }

                if !ble.events.isEmpty {
                    Section("Log") {
                        ForEach(ble.events.prefix(20)) { e in
                            HStack {
                                Text(e.text)
                                Spacer()
                                Text(e.date, style: .time).foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    }
                }

                Section {
                    ForEach(ble.sortedDevices) { d in DeviceRow(device: d) }
                } header: {
                    HStack {
                        Text("Nearby devices (\(ble.devices.count))")
                        Spacer()
                        Button("Clear") { ble.clearDevices() }.font(.caption)
                    }
                } footer: {
                    Text("Tap your brush to select it — the app stays connected and reads its real state. Tap ⓘ to inspect raw characteristics.")
                }

                Section("Credits") {
                    Text("Bao the panda is an original BrushWatch character. Pagoda and Pavilion by Poly by Google, Red Lantern by Sophie Kim — CC-BY 3.0, via poly.pizza.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Brush")
        }
    }

    private var linkText: String {
        switch ble.link {
        case .idle: "—"
        case .waiting: "Waiting for brush to wake…"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .unsupported: "Unsupported"
        }
    }

    private var bluetoothMessage: String {
        switch ble.bluetoothState {
        case .poweredOff: "Bluetooth is off"
        case .unauthorized: "Bluetooth permission denied — enable it in Settings"
        case .unsupported: "Bluetooth LE not supported (simulator?)"
        default: "Waiting for Bluetooth…"
        }
    }
}

func format(_ secs: Int) -> String { "\(secs / 60):\(String(format: "%02d", secs % 60))" }

struct StatusCard: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: ble.brushOn ? "bolt.fill" : "moon.zzz.fill")
                .font(.system(size: 44))
                .symbolEffect(.pulse, isActive: ble.brushOn)
            Text(title).font(.title.bold())
            if ble.brushOn {
                Text(ble.brushingTime.map(format) ?? "0:00").font(.title2.monospacedDigit())
            } else if let b = ble.brush {
                Text(b.name).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .foregroundStyle(ble.brushOn ? .white : .primary)
        .background(ble.brushOn ? Color.green : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut, value: ble.brushOn)
    }

    private var title: String {
        if ble.brushID == nil { return "Pick your brush below" }
        if ble.brushOn { return "BRUSHING" }
        return ble.link == .connected ? "Brush \(ble.handleStateText)" : "Brush asleep"
    }
}

struct DeviceRow: View {
    @EnvironmentObject var ble: BLEManager
    let device: SeenDevice
    @State private var showExplore = false

    var body: some View {
        HStack {
            Image(systemName: ble.brushID == device.id ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ble.brushID == device.id ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(device.name).fontWeight(device.looksLikeSonicare ? .semibold : .regular)
                    if device.looksLikeSonicare { Text("🪥") }
                }
                Text("RSSI \(device.rssi)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showExplore = true } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { ble.brushID = (ble.brushID == device.id) ? nil : device.id }
        .sheet(isPresented: $showExplore) { ExploreView(device: device) }
    }
}

struct ExploreView: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) var dismiss
    let device: SeenDevice

    var body: some View {
        NavigationStack {
            List {
                Section("Advertisement") {
                    LabeledContent("Name", value: device.name)
                    LabeledContent("iOS ID", value: device.id.uuidString).font(.caption)
                    if !device.serviceUUIDs.isEmpty {
                        LabeledContent("Services", value: device.serviceUUIDs.map(\.uuidString).joined(separator: "\n"))
                            .font(.caption)
                    }
                    if let m = device.manufacturerData {
                        LabeledContent("Mfg data", value: m.map { String(format: "%02X", $0) }.joined(separator: " "))
                            .font(.caption.monospaced())
                    }
                }
                Section {
                    Text(ble.exploreStatus[device.id] ?? "Not connected")
                    ForEach(ble.chars[device.id] ?? []) { c in
                        CharRow(c: c).onTapGesture { ble.read(c, on: device.id) }
                    }
                } header: {
                    Text("GATT characteristics")
                } footer: {
                    Text("Values that just changed turn orange. Tap a row to re-read it.")
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { ble.explore(device.id) }
            .onDisappear { ble.stopExploring(device.id) }
        }
    }
}

struct CharRow: View {
    let c: CharInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let fresh = c.lastChange.map { ctx.date.timeIntervalSince($0) < 2 } ?? false
            VStack(alignment: .leading, spacing: 3) {
                if let label = c.label { Text(label).font(.caption.bold()) }
                Text(c.uuid.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary)
                Text(c.hex).font(.body.monospaced())
                    .foregroundStyle(fresh ? .orange : .primary)
                Text("\(c.propsText) · \(c.updates) updates").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
