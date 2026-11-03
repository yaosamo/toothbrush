import CoreBluetooth
import Foundation

// MARK: - Sonicare GATT map
//
// From community reverse engineering (github.com/mtheli/philips_sonicare_ble, const.py).
// Applies to the "classic" protocol: Sonicare for Kids HX63xx, DiamondClean, ExpertClean…
// The newer Kids HX6600 and Series 7100 use the "Condor" protocol instead (not supported yet).
enum Sonicare {
    static let handleState   = CBUUID(string: "477EA600-A260-11E4-AE37-0002A5D54010") // uint8
    static let brushingState = CBUUID(string: "477EA600-A260-11E4-AE37-0002A5D54082") // uint8
    static let brushingTime  = CBUUID(string: "477EA600-A260-11E4-AE37-0002A5D54090") // uint16 LE, seconds
    static let battery       = CBUUID(string: "2A19")                                 // uint8, %
    static let condorService = CBUUID(string: "E50BA3C0-AF04-4564-92AD-FEF019489DE6")

    static let watched: Set<CBUUID> = [handleState, brushingState, brushingTime, battery]

    static let handleStates: [UInt8: String] = [
        0: "off", 1: "standby", 2: "run", 3: "charge", 4: "shutdown", 6: "validate", 7: "background",
    ]
    static let brushingStates: [UInt8: String] = [
        0: "off", 1: "on", 2: "pause", 3: "session complete", 4: "session aborted",
    ]
    static let handleRunning: UInt8 = 2
    static let brushingOn: UInt8 = 1
}

/// A device seen in a BLE advertisement.
struct SeenDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
    var serviceUUIDs: [CBUUID]
    var manufacturerData: Data?

    var looksLikeSonicare: Bool {
        let n = name.lowercased()
        if n.contains("sonicare") || n.contains("philips") { return true }
        return serviceUUIDs.contains { $0.uuidString.uppercased().hasPrefix("477EA600") || $0 == Sonicare.condorService }
    }
}

struct BrushEvent: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
}

/// A GATT characteristic found on a connected device.
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

    var label: String? {
        switch uuid {
        case Sonicare.handleState: "Handle state"
        case Sonicare.brushingState: "Brushing state"
        case Sonicare.brushingTime: "Brushing time"
        case Sonicare.battery: "Battery"
        default: nil
        }
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

enum Link: Equatable {
    case idle, waiting, connecting, connected, unsupported(String)
}

final class BLEManager: NSObject, ObservableObject {
    // MARK: Published state
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [UUID: SeenDevice] = [:]
    @Published var brushID: UUID? {
        didSet {
            UserDefaults.standard.set(brushID?.uuidString, forKey: "brushID")
            if oldValue != brushID { switchBrush(from: oldValue) }
        }
    }

    // Brush link + decoded state
    @Published private(set) var link: Link = .idle
    @Published private(set) var handleState: UInt8?
    @Published private(set) var brushingState: UInt8?
    @Published private(set) var brushingTime: Int?
    @Published private(set) var battery: Int?
    @Published private(set) var brushOn = false
    @Published private(set) var events: [BrushEvent] = []

    /// Characteristics per connected device (for the Explore sheet).
    @Published private(set) var chars: [UUID: [CharInfo]] = [:]
    @Published private(set) var exploreStatus: [UUID: String] = [:]

    // MARK: Private
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var exploring: Set<UUID> = []
    private var lastBrushingTime = 0

    override init() {
        super.init()
        if let s = UserDefaults.standard.string(forKey: "brushID") { brushID = UUID(uuidString: s) }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var sortedDevices: [SeenDevice] {
        devices.values.sorted {
            if $0.looksLikeSonicare != $1.looksLikeSonicare { return $0.looksLikeSonicare }
            return $0.rssi > $1.rssi
        }
    }

    var brush: SeenDevice? { brushID.flatMap { devices[$0] } }

    var handleStateText: String {
        guard let h = handleState else { return "—" }
        return Sonicare.handleStates[h] ?? "unknown (\(h))"
    }

    var brushingStateText: String {
        guard let b = brushingState else { return "—" }
        return Sonicare.brushingStates[b] ?? "unknown (\(b))"
    }

    func clearDevices() { devices = devices.filter { $0.key == brushID || peripherals[$0.key]?.state == .connected } }

    // MARK: Brush link

    private func switchBrush(from old: UUID?) {
        if let old, let p = peripherals[old], !exploring.contains(old) { central?.cancelPeripheralConnection(p) }
        resetBrushState()
        connectBrush()
    }

    private func resetBrushState() {
        handleState = nil; brushingState = nil; brushingTime = nil; battery = nil
        updateOn()
        link = brushID == nil ? .idle : .waiting
    }

    /// iOS connect requests never time out: the phone connects as soon as the brush wakes up and advertises.
    private func connectBrush() {
        guard let central, central.state == .poweredOn, let id = brushID else { return }
        let p = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let p else { link = .waiting; return }
        peripherals[id] = p
        if p.state == .disconnected {
            link = .waiting
            central.connect(p)
        }
    }

    private func updateOn() {
        let on = handleState == Sonicare.handleRunning || brushingState == Sonicare.brushingOn
        guard on != brushOn else { return }
        brushOn = on
        if on {
            lastBrushingTime = 0
            log("🪥 Brushing started")
        } else {
            let secs = lastBrushingTime
            log("✅ Brushing stopped — \(secs / 60):\(String(format: "%02d", secs % 60))")
        }
    }

    private func log(_ text: String) {
        events.insert(BrushEvent(date: Date(), text: text), at: 0)
        if events.count > 100 { events.removeLast() }
    }

    // MARK: Explore

    func explore(_ id: UUID) {
        guard let p = peripherals[id] else { return }
        exploring.insert(id)
        if p.state == .connected {
            // Brush link only subscribed to the known characteristics; open everything up for exploring.
            for ch in p.services?.flatMap({ $0.characteristics ?? [] }) ?? [] {
                if ch.properties.contains(.read) { p.readValue(for: ch) }
                if ch.properties.contains(.notify) || ch.properties.contains(.indicate) { p.setNotifyValue(true, for: ch) }
            }
            return
        }
        exploreStatus[id] = "Connecting…"
        central.connect(p)
    }

    func stopExploring(_ id: UUID) {
        exploring.remove(id)
        if id != brushID, let p = peripherals[id] { central.cancelPeripheralConnection(p) }
    }

    func read(_ c: CharInfo, on id: UUID) {
        guard let p = peripherals[id],
              let ch = p.services?.first(where: { $0.uuid == c.serviceUUID })?
                .characteristics?.first(where: { $0.uuid == c.uuid }) else { return }
        p.readValue(for: ch)
    }

    // MARK: Decoding

    private func handle(_ uuid: CBUUID, _ data: Data) {
        guard let first = data.first else { return }
        switch uuid {
        case Sonicare.handleState:
            handleState = first
        case Sonicare.brushingState:
            brushingState = first
        case Sonicare.brushingTime where data.count >= 2:
            brushingTime = Int(data[data.startIndex]) | Int(data[data.startIndex + 1]) << 8
            if brushOn, let t = brushingTime { lastBrushingTime = t }
        case Sonicare.battery:
            battery = Int(first)
        default:
            return
        }
        updateOn()
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        connectBrush()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown"
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

        if peripheral.identifier == brushID, peripheral.state == .disconnected { connectBrush() }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        if id == brushID { link = .connecting }
        exploreStatus[id] = "Connected — discovering services…"
        chars[id] = []
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        exploreStatus[peripheral.identifier] = "Failed to connect: \(error?.localizedDescription ?? "unknown")"
        if peripheral.identifier == brushID { connectBrush() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        exploreStatus[id] = "Disconnected\(error.map { " (\($0.localizedDescription))" } ?? "")"
        if id == brushID {
            // The brush drops the link when it goes to sleep: that means it's not running.
            if brushOn { log("💤 Brush went to sleep") }
            resetBrushState()
            connectBrush()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        if peripheral.identifier == brushID {
            let classic = services.contains { $0.uuid.uuidString.uppercased().hasPrefix("477EA600") }
            let condor = services.contains { $0.uuid == Sonicare.condorService }
            if !classic && condor {
                link = .unsupported("This brush uses Philips' newer \"Condor\" protocol (e.g. Kids HX6600). Not supported yet.")
            } else if !classic {
                link = .unsupported("No Sonicare service found on this device. Is it the brush?")
            }
        }
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let id = peripheral.identifier
        let isBrush = id == brushID
        for ch in service.characteristics ?? [] {
            chars[id, default: []].append(CharInfo(serviceUUID: service.uuid, uuid: ch.uuid, properties: ch.properties))
            // For the brush, only subscribe to what we need; for Explore, subscribe to everything.
            let wanted = !isBrush || exploring.contains(id) || Sonicare.watched.contains(ch.uuid)
            guard wanted else { continue }
            if ch.properties.contains(.read) { peripheral.readValue(for: ch) }
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: ch)
            }
        }
        exploreStatus[id] = "Connected — \(chars[id]?.count ?? 0) characteristics"
        if isBrush, link == .connecting { link = .connected }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = peripheral.identifier
        guard let value = characteristic.value else { return }
        if id == brushID { handle(characteristic.uuid, value) }

        guard let service = characteristic.service,
              let i = chars[id]?.firstIndex(where: { $0.uuid == characteristic.uuid && $0.serviceUUID == service.uuid })
        else { return }
        if chars[id]![i].value != nil && chars[id]![i].value != value { chars[id]![i].lastChange = Date() }
        chars[id]![i].value = value
        chars[id]![i].updates += 1
    }
}
