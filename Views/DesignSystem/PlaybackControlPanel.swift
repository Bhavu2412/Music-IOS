import AVKit
import MediaPlayer
import SwiftUI

struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsVolumeSlider = true
        for view in volumeView.subviews {
            if let slider = view as? UISlider {
                slider.tintColor = UIColor(DesignSystem.AppColors.accent)
            }
        }
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor(DesignSystem.AppColors.secondaryText)
        picker.activeTintColor = UIColor(DesignSystem.AppColors.accent)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct PlaybackControlPanel: View {
    @ObservedObject var playback: PlaybackService
    var showQueue: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            // MARK: - Shuffle and Repeat
            HStack {
                // Shuffle Button
                Button {
                    withAnimation(DesignSystem.Motion.spring) {
                        playback.toggleShuffle()
                    }
                    Haptics.impact(.medium)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(playback.isShuffled ? DesignSystem.AppColors.accent : DesignSystem.AppColors.secondaryText)

                        Circle()
                            .fill(playback.isShuffled ? DesignSystem.AppColors.accent : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .accessibilityLabel(playback.isShuffled ? "Shuffle active" : "Shuffle inactive")

                Spacer()

                // Repeat Button (off -> all -> one -> off)
                Button {
                    cycleRepeatMode()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: repeatIconName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(playback.repeatMode != .off ? DesignSystem.AppColors.accent : DesignSystem.AppColors.secondaryText)

                        Circle()
                            .fill(playback.repeatMode != .off ? DesignSystem.AppColors.accent : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .accessibilityLabel("Repeat: \(repeatModeLabel)")
            }
            .padding(.horizontal, 8)

            // MARK: - Main Transport Controls (Prev, Big Play/Pause, Next)
            HStack(spacing: 30) {
                // Previous Track
                Button {
                    playback.previous()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(DesignSystem.AppColors.primaryText)
                        .frame(width: 54, height: 54)
                        .glassCircle()
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .accessibilityLabel("Previous track")

                // Play / Pause Button (Large, glowing, morphing)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        playback.togglePlayback()
                    }
                    Haptics.impact(.medium)
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white, Color(white: 0.92)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 76, height: 76)
                            .shadow(color: DesignSystem.AppColors.accent.opacity(playback.isPlaying ? 0.35 : 0.15), radius: 18, y: 6)
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(DesignSystem.AppColors.accentContrastText)
                            .offset(x: playback.isPlaying ? 0 : 2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 76, height: 76)
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                // Next Track
                Button {
                    playback.next()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(DesignSystem.AppColors.primaryText)
                        .frame(width: 54, height: 54)
                        .glassCircle()
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .accessibilityLabel("Next track")
            }
            .padding(.vertical, 4)

            // MARK: - Volume Slider Bar
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.AppColors.secondaryText)

                SystemVolumeSlider()
                    .frame(height: 28)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.AppColors.secondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // MARK: - Bottom Utility Row (AirPlay & Queue)
            HStack {
                AirPlayRoutePicker()
                    .frame(width: 38, height: 38)
                    .accessibilityLabel("Audio output route")

                Spacer()

                if let current = playback.currentTrack {
                    Text(audioFormatLabel(for: current))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(DesignSystem.AppColors.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassCapsule()
                }

                Spacer()

                if let showQueue {
                    Button(action: showQueue) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DesignSystem.AppColors.secondaryText)
                            .frame(width: 38, height: 38)
                            .glassCircle()
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                    .accessibilityLabel("Queue")
                } else {
                    Color.clear.frame(width: 38, height: 38)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(18)
        .glassCard(cornerRadius: 28)
    }

    private var repeatIconName: String {
        switch playback.repeatMode {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    private var repeatModeLabel: String {
        switch playback.repeatMode {
        case .off: "Off"
        case .all: "All tracks"
        case .one: "One track"
        }
    }

    private func cycleRepeatMode() {
        withAnimation(DesignSystem.Motion.spring) {
            let next: QueueRepeatMode
            switch playback.repeatMode {
            case .off: next = .all
            case .all: next = .one
            case .one: next = .off
            }
            playback.setRepeatMode(next)
        }
        Haptics.impact(.medium)
    }

    private func audioFormatLabel(for track: Track) -> String {
        let ext = (track.originalFilename as NSString).pathExtension.uppercased()
        guard !ext.isEmpty else { return "AUDIO" }
        if ["FLAC", "WAV", "ALAC", "AIFF", "AIF"].contains(ext) { return "\(ext) • LOSSLESS" }
        if let bitrate = track.bitrate, bitrate > 0 { return "\(ext) • \(Int(bitrate / 1000)) KBPS" }
        return ext
    }
}
