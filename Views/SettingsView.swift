import SwiftUI

struct SettingsView: View {
    @AppStorage("music.feedURLs") private var feedURLsStorage: [String] = []
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @AppStorage(CloudSyncService.enabledKey) private var iCloudSync = true
    @ObservedObject private var playback = PlaybackService.shared
    @State private var sleepTimer = SleepTimerService.shared
    @State private var draftURL = ""
    @State private var sleepMinutes = 30
    @State private var documentsBytes: Int64 = 0
    @State private var cacheBytes: Int64 = 0
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.AppSpacing.s28) {
                settingsSection("PLAYBACK") {
                    settingsRow(.playbackSpeed, title: "Playback speed") {
                        Picker("Playback speed", selection: Binding(
                            get: { playback.playbackRate },
                            set: { playback.setPlaybackRate($0) }
                        )) {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                                Text("\(rate, specifier: "%g")×")
                                    .tag(Float(rate))
                            }
                        }
                        .labelsHidden()
                        .tint(DesignSystem.AppColors.accent)
                    }
                    sectionDivider
                    settingsRow(.equalizer, title: "Equalizer") {
                        Picker("Equalizer", selection: Binding(
                            get: { playback.eqPreset },
                            set: { playback.setEQPreset($0); Haptics.selection() }
                        )) {
                            ForEach(EqualizerPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .tint(DesignSystem.AppColors.accent)
                    }
                    EQCurve(gains: playback.eqPreset.bandGains)
                        .frame(height: 44)
                        .padding(.leading, 42)
                        .padding(.bottom, 8)
                        .animation(DesignSystem.Motion.spring, value: playback.eqPreset)
                    sectionDivider
                    settingsRow(.crossfade, title: "Crossfade") {
                        Stepper(
                            playback.crossfadeSeconds == 0 ? "Off" : "\(Int(playback.crossfadeSeconds)) s",
                            value: Binding(get: { playback.crossfadeSeconds }, set: { playback.setCrossfade($0) }),
                            in: 0...12,
                            step: 1
                        )
                        .font(DesignSystem.subhead.monospacedDigit())
                        .fixedSize()
                    }
                    sectionDivider
                    settingsToggle(.gapless, title: "Gapless playback", isOn: Binding(
                        get: { playback.isGaplessEnabled },
                        set: { playback.setGapless($0) }
                    ))
                    .disabled(playback.crossfadeSeconds > 0)
                    .opacity(playback.crossfadeSeconds > 0 ? 0.5 : 1)
                    if playback.crossfadeSeconds > 0 {
                        Text("Crossfade blends songs together, so gapless playback is off while it’s on.")
                            .font(DesignSystem.caption)
                            .foregroundStyle(DesignSystem.AppColors.secondaryText)
                            .padding(.leading, 42)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                settingsSection("LIBRARY AND OFFLINE") {
                    settingsToggle(.iCloud, title: "iCloud sync", isOn: Binding(
                        get: { iCloudSync },
                        set: { iCloudSync = $0; if $0 { CloudSyncService.shared.start() } }
                    ))
                    Text("Syncs favorites and playlists between your devices. Songs are matched by title and artist; audio files stay on each device.")
                        .font(DesignSystem.caption)
                        .foregroundStyle(DesignSystem.AppColors.secondaryText)
                        .padding(.leading, 42)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    sectionDivider
                    settingsRow(.offline, title: "Offline mode") {
                        Text("Automatic")
                            .font(DesignSystem.subhead)
                            .foregroundStyle(DesignSystem.AppColors.secondaryText)
                    }
                    sectionDivider
                    VStack(alignment: .leading, spacing: 12) {
                        settingsRow(.remoteFeeds, title: "Remote feeds") {
                            EmptyView()
                        }
                        ForEach(feedURLsStorage, id: \.self) { url in
                            HStack(spacing: 8) {
                                Text(url)
                                    .font(DesignSystem.subhead)
                                    .foregroundStyle(DesignSystem.AppColors.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                                Button(role: .destructive) {
                                    feedURLsStorage.removeAll { $0 == url }
                                } label: {
                                    AppIconView(icon: .delete, color: DesignSystem.AppColors.danger)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(DesignSystem.PremiumPressStyle())
                                .accessibilityLabel("Remove feed")
                            }
                            .padding(.leading, 38)
                        }
                        HStack(spacing: 8) {
                            TextField("https://example.com/feed.json", text: $draftURL)
                                .font(DesignSystem.subhead)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .submitLabel(.done)
                                .onSubmit(addFeed)
                                .accessibilityLabel("Remote feed URL")
                            Button(action: addFeed) {
                                Text("Add")
                                    .font(DesignSystem.body.weight(.semibold))
                                    .foregroundStyle(DesignSystem.AppColors.accent)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .disabled(draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.leading, 38)
                    }
                }

                settingsSection("SLEEP TIMER AND STORAGE") {
                    settingsRow(.sleepTimer, title: "Sleep timer") {
                        if sleepTimer.isEnabled {
                            Text(Duration.seconds(sleepTimer.remainingSeconds), format: .time(pattern: .minuteSecond))
                                .font(DesignSystem.subhead.monospacedDigit())
                                .foregroundStyle(DesignSystem.AppColors.accent)
                                .contentTransition(.numericText())
                        } else {
                            Stepper("\(sleepMinutes) min", value: $sleepMinutes, in: 5...120, step: 5)
                                .font(DesignSystem.subhead.monospacedDigit())
                                .fixedSize()
                        }
                    }
                    Group {
                        if sleepTimer.isEnabled {
                            DesignSystem.GlassButton(title: "Cancel timer", icon: .pause, action: {
                                sleepTimer.stop()
                            }, style: .secondary)
                        } else {
                            DesignSystem.GlassButton(title: "Start \(sleepMinutes)-minute timer", icon: .play, action: {
                                sleepTimer.start(minutes: sleepMinutes)
                                Haptics.notify()
                            }, style: .primary)
                        }
                    }
                    .padding(.leading, 42)
                    .padding(.vertical, 8)
                    sectionDivider
                    settingsRow(.storage, title: "Documents") {
                        Text(ByteCountFormatter.string(fromByteCount: documentsBytes, countStyle: .file))
                            .font(DesignSystem.subhead)
                            .foregroundStyle(DesignSystem.AppColors.secondaryText)
                    }
                    sectionDivider
                    settingsRow(.storage, title: "Cache") {
                        Text(ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))
                            .font(DesignSystem.subhead)
                            .foregroundStyle(DesignSystem.AppColors.secondaryText)
                    }
                    Button {
                        do {
                            try StorageManagerService().clearCache()
                            refreshStorage()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        HStack(spacing: 12) {
                            AppIconView(icon: .delete, color: DesignSystem.AppColors.danger)
                                .frame(width: 30, height: 30)
                                .background(DesignSystem.AppColors.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            Text("Clear cache")
                                .font(DesignSystem.body)
                                .foregroundStyle(DesignSystem.AppColors.danger)
                            Spacer()
                        }
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                }

                settingsSection("ACCESSIBILITY") {
                    settingsToggle(.haptics, title: "Use haptics", isOn: $hapticsEnabled)
                }
            }
            .padding(.horizontal, DesignSystem.AppSpacing.screen)
            .padding(.top, DesignSystem.AppSpacing.s16)
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
        .background(DesignSystem.AppColors.background)
        .task { refreshStorage() }
        .alert("Settings error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(DesignSystem.AppColors.border)
            .frame(height: 1)
            .padding(.leading, 42)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.AppSpacing.s12) {
            Text(title)
                .font(DesignSystem.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                .padding(.leading, 4)
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassCard(cornerRadius: DesignSystem.AppRadius.card)
        }
    }

    private func settingsRow<Accessory: View>(
        _ icon: AppIcon,
        title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            iconTile(icon)
            Text(title)
                .font(DesignSystem.body)
                .foregroundStyle(DesignSystem.AppColors.primaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            accessory()
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func settingsToggle(
        _ icon: AppIcon,
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            iconTile(icon)
            Toggle(title, isOn: isOn)
                .font(DesignSystem.body)
                .tint(DesignSystem.AppColors.accent)
                .foregroundStyle(DesignSystem.AppColors.primaryText)
        }
        .frame(minHeight: 52)
    }

    private func iconTile(_ icon: AppIcon) -> some View {
        AppIconView(icon: icon, size: .row, color: DesignSystem.AppColors.accent)
            .frame(width: 30, height: 30)
            .background(DesignSystem.AppColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private func refreshStorage() {
        let storage = StorageManagerService()
        documentsBytes = storage.documentsUsage()
        cacheBytes = storage.cachedUsage()
    }

    private func addFeed() {
        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            errorMessage = "Enter a valid feed URL."
            return
        }
        if !feedURLsStorage.contains(trimmed) {
            feedURLsStorage.append(trimmed)
        }
        draftURL = ""
    }
}

/// Small visual of the selected EQ curve: one bar per band, centered on 0 dB.
private struct EQCurve: View {
    let gains: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(gains.enumerated()), id: \.offset) { _, gain in
                GeometryReader { geometry in
                    let half = geometry.size.height / 2
                    let height = max(CGFloat(abs(gain)) / 6 * half, 2)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.AppColors.accent.opacity(gain == 0 ? 0.35 : 0.9))
                        .frame(height: height)
                        .offset(y: gain >= 0 ? half - height : half)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
