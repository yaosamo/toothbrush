import CoreBluetooth
import Foundation

/// A device seen in a BLE advertisement.
struct SeenDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
    var serviceUUIDs: [CBUUID]
    var manufacturerData: Data?

    /// Philips Sonicare brushes advertise names like "Philips Sonicare" and use
    /// custom service UUIDs starting with 477ea600-a260-11e4-ae37-0002a5d5.
    var looksLikeSonicare: Bool {
        let n = name.lowercased()
        if n.contains("sonicare") || n.contains("philips") { return true }
        return serviceUUIDs.contains { $0.uuidString.uppercased().hasPrefix("477EA600") }
    }
}

struct BrushEvent: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
}

/// A GATT characteristic found while exploring a connected device.
struct CharInfo: Identifiable {
    var id: String { "\(serviceUUID.uuidString)/\(uuid.uuidString)" }
    let serviceUUID: CBUUID
    let uuid: CBUUID
    let properties: CBCharacteristicProperties
    var value: Data?
    var updates: Int = 0
    var lastChange: Date?

    var hex: String {
        guard let value, !value.isEmpty else { return "—" }
        return value.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var propsText: String {
        var p: [String] = []
        if properties.contains(.read) { p.append("read") }
        if properties.contains(.write) || properties.contains(.writeWithoutResponse) { p.append("write") }
        if properties.contains(.notify) { p.append("notify") }
        if properties.contains(.indicate) { p.append("indicate") }
        return p.joined(separator: " · ")
    }
}

final class BLEManager: NSObject, ObservableObject {
    // MARK: Published state
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [UUID: SeenDevice] = [:]
    @Published private(set) var brushOn = false
    @Published private(set) var onSince: Date?
    @Published private(set) var events: [BrushEvent] = []
    @Published var brushID: UUID? {
        didSet { UserDefaults.standard.set(brushID?.uuidString, forKey: "brushID") }
    }

    // Explore (GATT) state
    @Published private(set) var exploring: UUID?
    @Published private(set) var connectionStatus = ""
    @Published private(set) var characteristics: [CharInfo] = []

    /// How long without an advertisement before we decide the brush went to sleep.
    let offTimeout: TimeInterval = 4

    // MARK: Private
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var timer: Timer?

    override init() {
        super.init()
        if let s = UserDefaults.standard.string(forKey: "brushID") { brushID = UUID(uuidString: s) }
        central = CBCentralManager(delegate: self, queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updatePresence()
        }
    }

    var sortedDevices: [SeenDevice] {
        devices.values.sorted {
            if $0.looksLikeSonicare != $1.looksLikeSonicare { return $0.looksLikeSonicare }
            return $0.rssi > $1.rssi
        }
    }

    var brush: SeenDevice? { brushID.flatMap { devices[$0] } }

    func clearDevices() { devices = devices.filter { $0.key == brushID } }

    // MARK: Scanning

    private func startScan() {
        guard central.state == .poweredOn else { return }
        // Duplicates on so every advertisement refreshes lastSeen (works in foreground only on iOS).
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    // MARK: Presence detection

    private func updatePresence() {
        guard let id = brushID else {
            if brushOn { setBrushOn(false) }
            return
        }
        // While connected the brush stops advertising, so the connection itself counts as "on".
        let connected = peripherals[id]?.state == .connected
        let recentlySeen = devices[id].map { Date().timeIntervalSince($0.lastSeen) < offTimeout } ?? false
        let on = connected || recentlySeen
        if on != brushOn { setBrushOn(on) }
    }

    private func setBrushOn(_ on: Bool) {
        brushOn = on
        if on {
            onSince = Date()
            log("🪥 Brush turned ON")
        } else {
            let end = min(brush?.lastSeen ?? Date(), Date())
            if let start = onSince {
                let secs = Int(max(0, end.timeIntervalSince(start)))
                log("💤 Brush OFF — awake for \(secs / 60):\(String(format: "%02d", secs % 60))")
            } else {
                log("💤 Brush OFF")
            }
            onSince = nil
        }
    }

    private func log(_ text: String) {
        events.insert(BrushEvent(date: Date(), text: text), at: 0)
        if events.count > 100 { events.removeLast() }
    }

    // MARK: Explore (connect + dump GATT)

    func explore(_ id: UUID) {
        if let current = exploring, let p = peripherals[current] { central.cancelPeripheralConnection(p) }
        guard let p = peripherals[id] else { return }
        exploring = id
        characteristics = []
        connectionStatus = "Connecting…"
        central.connect(p)
    }

    func stopExploring() {
        if let id = exploring, let p = peripherals[id] { central.cancelPeripheralConnection(p) }
        exploring = nil
        characteristics = []
        connectionStatus = ""
    }

    func read(_ c: CharInfo) {
        guard let p = exploring.flatMap({ peripherals[$0] }),
              let ch = p.services?.first(where: { $0.uuid == c.serviceUUID })?
                .characteristics?.first(where: { $0.uuid == c.uuid }) else { return }
        p.readValue(for: ch)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state == .poweredOn { startScan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? "Unknown"
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        var d = devices[peripheral.identifier] ?? SeenDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue,
                                                            lastSeen: Date(), serviceUUIDs: [], manufacturerData: nil)
        if name != "Unknown" { d.name = name }
        if RSSI.intValue != 127 { d.rssi = RSSI.intValue }
        d.lastSeen = Date()
        if !services.isEmpty { d.serviceUUIDs = services }
        if let mfg { d.manufacturerData = mfg }
        devices[peripheral.identifier] = d
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = "Connected — discovering services…"
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "Failed to connect: \(error?.localizedDescription ?? "unknown")"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == exploring else { return }
        connectionStatus = "Disconnected\(error.map { " (\($0.localizedDescription))" } ?? "")"
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            characteristics.append(CharInfo(serviceUUID: service.uuid, uuid: ch.uuid, properties: ch.properties))
            if ch.properties.contains(.read) { peripheral.readValue(for: ch) }
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: ch)
            }
        }
        connectionStatus = "Connected — \(characteristics.count) characteristics"
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let service = characteristic.service,
              let i = characteristics.firstIndex(where: { $0.uuid == characteristic.uuid && $0.serviceUUID == service.uuid })
        else { return }
        let new = characteristic.value
        if characteristics[i].value != nil && characteristics[i].value != new {
            characteristics[i].lastChange = Date()
        }
        characteristics[i].value = new
        characteristics[i].updates += 1
    }
}
