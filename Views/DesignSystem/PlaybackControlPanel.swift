import SwiftUI

struct PlaybackControlPanel: View {
    @ObservedObject var playback: PlaybackService
    @State private var modeAnimationTrigger = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Label("NOW PLAYING", systemImage: AppIcon.waveform.symbolName())
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(DesignSystem.AppColors.secondaryText)
                Spacer()
                Button(action: cyclePlaybackMode) {
                    AppIconView(
                        icon: playbackModeSymbol,
                        size: .playerSecondary,
                        weight: .semibold,
                        color: playbackMode == .normal ? .secondary : DesignSystem.AppColors.accent
                    )
                        .frame(width: 44, height: 44)
                        .glassCircle()
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: modeAnimationTrigger)
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .accessibilityLabel("Playback mode: \(playbackModeName)")
                .accessibilityHint("Cycles between normal, shuffle, and repeat")
            }

            HStack(spacing: 8) {
                skipButton(.skipBack, label: "Back 15 seconds") {
                    playback.skip(by: -15)
                }
                transportButton(.previous, label: "Previous track") {
                    playback.previous()
                    Haptics.impact(.light)
                }
                playButton
                transportButton(.next, label: "Next track") {
                    playback.next()
                    Haptics.impact(.light)
                }
                skipButton(.skipForward, label: "Forward 15 seconds") {
                    playback.skip(by: 15)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.top, 12)

        }
        .padding(20)
        .glassCard(cornerRadius: 28)
    }

    private var playbackMode: PlaybackMode {
        if playback.repeatMode != .off { return .repeatAll }
        return playback.isShuffled ? .shuffle : .normal
    }

    private var playbackModeSymbol: AppIcon {
        switch playbackMode {
        case .normal: .playbackModeNormal
        case .shuffle: .shuffle
        case .repeatAll: .repeatAll
        }
    }

    private var playbackModeName: String {
        switch playbackMode {
        case .normal: "Normal"
        case .shuffle: "Shuffle"
        case .repeatAll: "Repeat"
        }
    }

    private func cyclePlaybackMode() {
        let nextMode: PlaybackMode
        switch playbackMode {
        case .normal: nextMode = .shuffle
        case .shuffle: nextMode = .repeatAll
        case .repeatAll: nextMode = .normal
        }
        withAnimation(DesignSystem.Motion.spring) {
            modeAnimationTrigger.toggle()
            switch nextMode {
            case .normal:
                if playback.isShuffled { playback.toggleShuffle() }
                playback.setRepeatMode(.off)
            case .shuffle:
                playback.setRepeatMode(.off)
                if !playback.isShuffled { playback.toggleShuffle() }
            case .repeatAll:
                if playback.isShuffled { playback.toggleShuffle() }
                playback.setRepeatMode(.all)
            }
        }
    }

    private enum PlaybackMode {
        case normal
        case shuffle
        case repeatAll
    }

    private var playButton: some View {
        Button {
            withAnimation(DesignSystem.Motion.spring) {
                playback.togglePlayback()
            }
            Haptics.impact(.medium)
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)

                AppIconView(
                    icon: playback.isPlaying ? .pause : .play,
                    size: .playerSecondary,
                    weight: .semibold,
                    color: DesignSystem.AppColors.accentContrastText
                )
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: playback.isPlaying ? 0 : 2)
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(DesignSystem.PremiumPressStyle())
        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
    }

    private func transportButton(
        _ icon: AppIcon,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AppIconView(icon: icon, size: .transport, weight: .regular)
                .frame(width: 44, height: 44)
                .glassCircle()
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(DesignSystem.PremiumPressStyle())
        .accessibilityLabel(label)
    }

    private func skipButton(
        _ icon: AppIcon,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Haptics.impact(.light)
        } label: {
            AppIconView(icon: icon, size: .skip)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(DesignSystem.PremiumPressStyle())
        .accessibilityLabel(label)
    }

}
