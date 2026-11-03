import SwiftUI

@main
struct FifteeniOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Notifier.shared.setUp()
        LiveActivityController.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(TimerEngine.shared)
                .environment(Preferences.shared)
                .environment(HistoryStore.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { TimerEngine.shared.refresh() }
        }
    }
}

/// One timer, filling the screen. Controls float at the bottom as glass pills.
struct RootView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @AppStorage("onboarded") private var onboarded = false
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height * 1.15
            let dial = min(geo.size.width - 48, geo.size.height * (landscape ? 0.6 : 0.5), 560)
            VStack(spacing: 0) {
                PhaseHeader()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer(minLength: 12)
                DialView(lineWidth: dial > 380 ? 9 : 7)
                    .frame(width: dial, height: dial)
                IntentionField()
                    .font(.title3)
                    .padding(.horizontal, 32)
                    .padding(.top, landscape ? 16 : 32)
                Spacer(minLength: 12)
                if prefs.showTodayProgress {
                    TodayLine()
                        .padding(.bottom, 14)
                }
                ControlPills()
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .environment(\.appActions, AppActions(showHistory: { showHistory = true },
                                              showSettings: { showSettings = true }))
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                HistoryView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showHistory = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showSettings) { IOSSettingsView() }
        .fullScreenCover(isPresented: .constant(!onboarded)) {
            OnboardingView { onboarded = true }
        }
        .onChange(of: engine.state, initial: true) { updateIdleTimer() }
        .onChange(of: prefs.keepScreenOn) { updateIdleTimer() }
        .persistentSystemOverlays(engine.state == .running ? .hidden : .automatic)
        .preferredColorScheme(prefs.appearance.colorScheme)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn && engine.state == .running
    }
}

struct IOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        NavigationStack {
            Form {
                TimerSettingsSection()
                SoundSettingsSection()
                DisplaySettingsSection()
                Section {
                    Toggle("Live Activity", isOn: $prefs.liveActivity)
                    Toggle("Keep screen on while running", isOn: $prefs.keepScreenOn)
                } header: {
                    Text("Lock Screen")
                } footer: {
                    Text("The countdown stays on your Lock Screen and in the Dynamic Island.")
                }
                Section {
                    NavigationLink {
                        AboutView()
                            .navigationTitle("About")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("About Fifteen", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One screen, shown once.
struct OnboardingView: View {
    var done: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: appeared ? 0.78 : 0)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 140, height: 140)
            .animation(.spring(duration: 1.4, bounce: 0.2).delay(0.2), value: appeared)

            VStack(spacing: 10) {
                Text("One timer. One thing.")
                    .font(.largeTitle.weight(.semibold))
                Text("Focus for 25 minutes, then rest for 5. After four rounds, take a longer break.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                Label("Drag around the ring to set the time.", systemImage: "hand.draw")
                Label("Tap the ring to start or pause.", systemImage: "hand.tap")
                Label("Your countdown follows you to the Lock Screen.", systemImage: "lock")
            }
            .font(.callout)
            Spacer()
            Button {
                Notifier.shared.requestAuthorizationIfNeeded()
                done()
            } label: {
                Text("Begin").frame(maxWidth: .infinity).pill(prominent: true)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .onAppear { appeared = true }
    }
}
