import SwiftUI

struct SettingsView: View {
    @AppStorage("music.feedURLs") private var feedURLsStorage: [String] = []
    @State private var draftURL = ""
    @State private var playbackRate: Float = 1.0
    @State private var sleepMinutes = 30
    @State private var selectedPreset = EqualizerPreset.flat
    @State private var crossfadeSeconds = 1.0
    @State private var isGaplessEnabled = true
    @State private var isAutoMergeEnabled = false
    @State private var isDynamicTypeEnabled = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.AppSpacing.s28) {
                settingsSection("PLAYBACK") {
                    settingsRow(.equalizer, title: "EQ preset") {
                        Picker("EQ preset", selection: $selectedPreset) {
                            ForEach(EqualizerPreset.allCases, id: \.self) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .tint(DesignSystem.AppColors.accent)
                    }
                    sectionDivider
                    settingsRow(.playbackSpeed, title: "Playback speed") {
                        Picker("Playback speed", selection: $playbackRate) {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                                Text(rate, format: .number.precision(.fractionLength(2)))
                                    .tag(Float(rate))
                            }
                        }
                        .labelsHidden()
                        .tint(DesignSystem.AppColors.accent)
                    }
                    sectionDivider
                    settingsRow(.crossfade, title: "Crossfade") {
                        Stepper(
                            "\(crossfadeSeconds, specifier: "%.1f")s",
                            value: $crossfadeSeconds,
                            in: 0...5,
                            step: 0.5
                        )
                        .labelsHidden()
                    }
                    sectionDivider
                    settingsToggle(.gapless, title: "Gapless playback", isOn: $isGaplessEnabled)
                }

                settingsSection("LIBRARY AND OFFLINE") {
                    settingsToggle(.merge, title: "Auto-merge duplicates", isOn: $isAutoMergeEnabled)
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
                        Stepper("\(sleepMinutes) min", value: $sleepMinutes, in: 5...120, step: 5)
                            .labelsHidden()
                    }
                    HStack(spacing: 12) {
                        DesignSystem.GlassButton(title: "Start", icon: .play, action: {
                            SleepTimerService().start(minutes: sleepMinutes)
                        }, style: .primary)
                        DesignSystem.GlassButton(title: "Stop", icon: .pause, action: {
                            SleepTimerService().stop()
                        }, style: .secondary)
                    }
                    .padding(.leading, 42)
                    .padding(.vertical, 8)
                    sectionDivider
                    settingsRow(.storage, title: "Documents") {
                        let storage = StorageManagerService()
                        Text(ByteCountFormatter.string(fromByteCount: storage.documentsUsage(), countStyle: .file))
                            .font(DesignSystem.subhead)
                            .foregroundStyle(DesignSystem.AppColors.secondaryText)
                    }
                    sectionDivider
                    settingsRow(.storage, title: "Cache") {
                        let storage = StorageManagerService()
                        Text(ByteCountFormatter.string(fromByteCount: storage.cachedUsage(), countStyle: .file))
                            .font(DesignSystem.subhead)
                            .foregroundStyle(DesignSystem.AppColors.secondaryText)
                    }
                    Button {
                        do {
                            try StorageManagerService().clearCache()
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
                    settingsToggle(.textSize, title: "Dynamic Type", isOn: $isDynamicTypeEnabled)
                    sectionDivider
                    settingsToggle(.haptics, title: "Use haptics", isOn: .constant(true))
                }
            }
            .padding(.horizontal, DesignSystem.AppSpacing.screen)
            .padding(.top, DesignSystem.AppSpacing.s16)
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
        .background(DesignSystem.AppColors.background)
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
