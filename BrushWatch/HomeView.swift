import SwiftUI

/// The main screen: the temple scene with the panda, a brushing HUD and the achievement shelf.
struct HomeView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var store: AchievementStore
    @StateObject private var director = PandaDirector()
    @State private var showSetup = false
    @State private var selected: Achievement?

    private let goal = 120

    var body: some View {
        ZStack {
            TempleView(director: director)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if ble.brushOn { brushingTimer.transition(.scale.combined(with: .opacity)) }
                Spacer()
                shelf
            }
            .padding(.horizontal, 16)

            if let a = store.justUnlocked { unlockedToast(a) }
        }
        .animation(.spring(duration: 0.4), value: ble.brushOn)
        .animation(.spring(duration: 0.5), value: store.justUnlocked?.id)
        .sheet(isPresented: $showSetup) { BrushSetupView().environmentObject(ble).environmentObject(store) }
        .onChange(of: ble.brushOn) { _, on in director.setBrushing(on) }
        .onChange(of: store.justUnlocked?.id) { _, id in if id != nil { director.celebrate() } }
        .onAppear {
            ble.onSessionEnded = { [store] secs in store.record(seconds: secs) }
            // Test hook: `simctl launch ... -simulateBrushing` starts a fake session after the scene loads.
            if ProcessInfo.processInfo.arguments.contains("-simulateBrushing") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { ble.simulate(true) }
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { showSetup = true } label: {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 10, height: 10)
                    Text(statusText).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            Label("\(store.totalSessions)", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.top, 8)
    }

    private var statusText: String {
        if ble.brushOn { return "Brushing" }
        if ble.brushID == nil { return "Connect brush" }
        switch ble.link {
        case .connected: return "Brush ready"
        case .unsupported: return "Brush not supported"
        default: return "Brush asleep"
        }
    }

    private var statusColor: Color {
        if ble.brushOn { return .green }
        if case .connected = ble.link { return .mint }
        return .orange
    }

    // MARK: Brushing timer

    private var brushingTimer: some View {
        let t = ble.brushingTime ?? 0
        return ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(1, CGFloat(t) / CGFloat(goal)))
                .stroke(t >= goal ? Color.yellow : Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: t)
            Text(format(t)).font(.title.bold().monospacedDigit()).foregroundStyle(.white)
                .shadow(radius: 4)
        }
        .frame(width: 110, height: 110)
        .offset(x: 120, y: -80)
    }

    // MARK: Achievement shelf

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let a = selected {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.title).font(.headline)
                    Text(store.unlocked[a.id] != nil ? "Earned! \(a.detail)" : a.detail)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Achievements.all) { a in
                        let earned = store.unlocked[a.id] != nil
                        Button { selected = (selected?.id == a.id) ? nil : a } label: {
                            Text(a.emoji)
                                .font(.system(size: 30))
                                .grayscale(earned ? 0 : 1)
                                .opacity(earned ? 1 : 0.45)
                                .frame(width: 56, height: 56)
                                .background(earned ? Color.yellow.opacity(0.35) : Color.white.opacity(0.25),
                                            in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16)
                                    .stroke(selected?.id == a.id ? Color.white : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: selected?.id)
    }

    // MARK: Unlock toast

    private func unlockedToast(_ a: Achievement) -> some View {
        VStack(spacing: 6) {
            Text(a.emoji).font(.system(size: 64))
            Text("Achievement unlocked!").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
            Text(a.title).font(.title2.bold())
            Text(a.detail).font(.subheadline).foregroundStyle(.secondary)
            Button("Yay!") { store.justUnlocked = nil }
                .buttonStyle(.borderedProminent).tint(.orange).padding(.top, 6)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(32)
        .offset(y: -140)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}
