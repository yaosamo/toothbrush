import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager

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
                    Text("Turn the brush on, then tap the device that appears — Sonicare-looking ones are listed first. Tap ⓘ to connect and inspect its characteristics.")
                }
            }
            .navigationTitle("BrushWatch")
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

struct StatusCard: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: ble.brushOn ? "bolt.fill" : "moon.zzz.fill")
                .font(.system(size: 44))
                .symbolEffect(.pulse, isActive: ble.brushOn)
            Text(ble.brushID == nil ? "Pick your brush below" : (ble.brushOn ? "BRUSH ON" : "Brush off"))
                .font(.title.bold())
            if let since = ble.onSince {
                Text(since, style: .timer).font(.title2.monospacedDigit())
            } else if let b = ble.brush {
                Text("\(b.name) · last seen \(b.lastSeen.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .foregroundStyle(ble.brushOn ? .white : .primary)
        .background(ble.brushOn ? Color.green : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut, value: ble.brushOn)
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
                Text("RSSI \(device.rssi) · \(age)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showExplore = true } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { ble.brushID = (ble.brushID == device.id) ? nil : device.id }
        .sheet(isPresented: $showExplore) { ExploreView(device: device) }
    }

    private var age: String {
        let s = Int(Date().timeIntervalSince(device.lastSeen))
        return s < 2 ? "now" : "\(s)s ago"
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
                    Text(ble.connectionStatus.isEmpty ? "Not connected" : ble.connectionStatus)
                    ForEach(ble.characteristics) { c in
                        CharRow(c: c).onTapGesture { ble.read(c) }
                    }
                } header: {
                    Text("GATT characteristics")
                } footer: {
                    Text("Notify characteristics are subscribed automatically. Values that just changed turn orange — press the brush button and watch which one moves. Tap a row to re-read it.")
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { ble.stopExploring(); dismiss() }
                }
            }
            .onAppear { ble.explore(device.id) }
        }
    }
}

struct CharRow: View {
    let c: CharInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let fresh = c.lastChange.map { ctx.date.timeIntervalSince($0) < 2 } ?? false
            VStack(alignment: .leading, spacing: 3) {
                Text(c.uuid.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary)
                Text(c.hex).font(.body.monospaced())
                    .foregroundStyle(fresh ? .orange : .primary)
                Text("\(c.propsText) · \(c.updates) updates").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
