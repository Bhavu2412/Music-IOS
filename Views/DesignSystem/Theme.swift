import SwiftUI
import UIKit

enum DesignSystem {
    enum AppColors {
        static let background = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.043, blue: 0.063, alpha: 1)
                : UIColor.systemGroupedBackground
        })
        static let backgroundSecondary = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.071, green: 0.078, blue: 0.11, alpha: 1)
                : UIColor.secondarySystemGroupedBackground
        })
        static let card = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.07)
                : UIColor.white.withAlphaComponent(0.86)
        })
        static let border = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.1)
        })
        static let accent = Color(red: 0.486, green: 0.514, blue: 1)
        static let accentContrastText = Color(red: 0.039, green: 0.043, blue: 0.063)
        static let primaryText = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.94)
                : UIColor.black.withAlphaComponent(0.94)
        })
        static let secondaryText = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.64)
                : UIColor.black.withAlphaComponent(0.64)
        })
        static let tertiaryText = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.5)
                : UIColor.black.withAlphaComponent(0.44)
        })
        static let muted = Color.secondary
        static let success = Color(red: 0.298, green: 0.839, blue: 0.627)
        static let warning = Color(red: 1, green: 0.722, blue: 0.302)
        static let danger = Color(red: 1, green: 0.42, blue: 0.42)
    }

    enum AppSpacing {
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s24: CGFloat = 24
        static let s28: CGFloat = 28
        static let s32: CGFloat = 32
        static let screen: CGFloat = 20
    }

    enum AppRadius {
        static let card: CGFloat = 20
        static let medium: CGFloat = 12
        static let small: CGFloat = 8
        static let artworkGrid: CGFloat = 20
        static let playerArtwork: CGFloat = 28
        static let button: CGFloat = 999
    }

    enum Shadows {
        static let soft = ShadowStyle(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
    }

    enum Motion {
        static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    }

    struct PremiumPressStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(configuration.isPressed ? 0.78 : 1)
                .animation(
                    reduceMotion ? nil : DesignSystem.Motion.spring,
                    value: configuration.isPressed
                )
        }
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let navigationTitle = Font.system(.title, design: .rounded).weight(.semibold)
    static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .rounded)
    static let subhead = Font.system(.subheadline, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)

    struct GlassButton: View {
        let title: String
        let icon: AppIcon
        let action: () -> Void
        let style: Style
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        enum Style: Equatable {
            case primary
            case secondary
            case destructive
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    AppIconView(
                        icon: icon,
                        size: .row,
                        weight: .semibold,
                        color: style == .primary ? DesignSystem.AppColors.accentContrastText : DesignSystem.AppColors.accent
                    )
                    Text(title)
                        .font(DesignSystem.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 16)
                .foregroundStyle(style == .primary ? DesignSystem.AppColors.accentContrastText : style == .destructive ? DesignSystem.AppColors.danger : DesignSystem.AppColors.primaryText)
                .modifier(LiquidGlassCapsuleModifier())
                .overlay(
                    Capsule().stroke(style == .destructive ? Color.clear : DesignSystem.AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(DesignSystem.PremiumPressStyle())
        }
    }

    struct GlassSearchBar: View {
        @Binding var text: String
        let placeholder: String
        var onClear: (() -> Void)? = nil
        var focus: FocusState<Bool>.Binding? = nil

        var body: some View {
            HStack(spacing: 12) {
                AppIconView(icon: .search, size: .row)
                Group {
                    if let focus {
                        TextField(placeholder, text: $text)
                            .focused(focus)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(DesignSystem.AppColors.primaryText)
                if !text.isEmpty {
                    Button {
                        text = ""
                        onClear?()
                    } label: {
                        AppIconView(icon: .clear, size: .row)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .glassCapsule()
            .animation(DesignSystem.Motion.spring, value: text.isEmpty)
        }
    }

    struct SectionHeader: View {
        let title: String
        var actionTitle: String?
        var action: (() -> Void)?

        var body: some View {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignSystem.AppColors.primaryText)
                    .lineLimit(1)
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(DesignSystem.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.AppColors.accent)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 12)
        }
    }

    struct EmptyStateView: View {
        let title: String
        let message: String
        let icon: AppIcon
        var actionTitle: String?
        var actionIcon: AppIcon = .add
        var action: (() -> Void)?

        var body: some View {
            VStack(spacing: 16) {
                AppIconView(icon: icon, size: .emptyState, color: DesignSystem.AppColors.accent)
                    .frame(width: 96, height: 96)
                    .background(DesignSystem.AppColors.card, in: Circle())
                    .overlay {
                        Circle().stroke(DesignSystem.AppColors.border, lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(title)
                        .font(DesignSystem.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.AppColors.primaryText)
                        .lineLimit(2)
                    Text(message)
                        .font(DesignSystem.subhead)
                        .foregroundStyle(DesignSystem.AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle, let action {
                    DesignSystem.GlassButton(
                        title: actionTitle,
                        icon: actionIcon,
                        action: action,
                        style: .primary
                    )
                    .frame(maxWidth: 260)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(24)
        }
    }

    struct LoadingRowsView: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var shimmer = false

        var body: some View {
            VStack(spacing: DesignSystem.AppSpacing.s12) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: DesignSystem.AppSpacing.s12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: DesignSystem.AppSpacing.s8) {
                            Capsule().frame(height: 15)
                            Capsule().frame(width: 120, height: 13)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(DesignSystem.AppColors.tertiaryText.opacity(0.18))
                    .frame(height: 68)
                }
            }
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            DesignSystem.AppColors.primaryText.opacity(0),
                            DesignSystem.AppColors.primaryText.opacity(0.12),
                            DesignSystem.AppColors.primaryText.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.7)
                    .offset(x: shimmer ? geometry.size.width : -geometry.size.width)
                }
                .clipped()
            }
            .accessibilityLabel("Loading")
            .accessibilityAddTraits(.updatesFrequently)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
            .onDisappear {
                shimmer = false
            }
        }
    }

    struct ArtworkView: View {
        let data: Data?
        let size: CGFloat
        var placeholderKey = "Music"
        var cornerRadius: CGFloat? = nil

        var body: some View {
            Group {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    AlbumArtworkPlaceholder(key: placeholderKey)
                }
            }
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                    .stroke(DesignSystem.AppColors.border.opacity(0.65), lineWidth: 1)
                    .padding(1)
            }
            .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
            .shadow(
                color: DesignSystem.Shadows.soft.color,
                radius: DesignSystem.Shadows.soft.radius,
                x: DesignSystem.Shadows.soft.x,
                y: DesignSystem.Shadows.soft.y
            )
            .accessibilityHidden(true)
        }

        private var resolvedCornerRadius: CGFloat {
            cornerRadius ?? (size >= 240 ? 28 : size >= 64 ? 20 : 12)
        }
    }

    struct ArtistAvatar: View {
        let name: String
        var size: CGFloat = 52

        var body: some View {
            ZStack {
                Circle()
                    .fill(ArtworkPalette.gradient(for: name))
                Text(initials)
                    .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignSystem.AppColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: size, height: size)
            .overlay {
                Circle().stroke(DesignSystem.AppColors.border.opacity(0.65), lineWidth: 1)
            }
            .shadow(
                color: DesignSystem.Shadows.soft.color,
                radius: DesignSystem.Shadows.soft.radius,
                x: 0,
                y: 8
            )
            .accessibilityLabel(name)
        }

        private var initials: String {
            let words = name.split(whereSeparator: \.isWhitespace)
            let letters = words.prefix(2).compactMap(\.first)
            return letters.isEmpty ? "?" : String(letters).uppercased()
        }
    }

    private struct AlbumArtworkPlaceholder: View {
        let key: String

        var body: some View {
            ZStack {
                ArtworkPalette.gradient(for: key)
                AppIconView(icon: .songs, size: .artworkPlaceholder, color: .white.opacity(0.4))
            }
        }
    }

    private enum ArtworkPalette {
        private static let palettes: [(Color, Color)] = [
            (Color(red: 0.24, green: 0.31, blue: 0.50), Color(red: 0.10, green: 0.14, blue: 0.25)),
            (Color(red: 0.43, green: 0.29, blue: 0.43), Color(red: 0.17, green: 0.12, blue: 0.24)),
            (Color(red: 0.25, green: 0.39, blue: 0.38), Color(red: 0.10, green: 0.20, blue: 0.21)),
            (Color(red: 0.48, green: 0.34, blue: 0.25), Color(red: 0.21, green: 0.15, blue: 0.13)),
            (Color(red: 0.30, green: 0.37, blue: 0.49), Color(red: 0.12, green: 0.16, blue: 0.25)),
            (Color(red: 0.40, green: 0.35, blue: 0.27), Color(red: 0.18, green: 0.16, blue: 0.13))
        ]

        static func gradient(for key: String) -> LinearGradient {
            var hash: UInt64 = 14_695_981_039_346_656_037
            for byte in key.lowercased().utf8 {
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
            let colors = palettes[Int(hash % UInt64(palettes.count))]
            return LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    struct GlassTabBar: View {
        @Binding var selection: LibraryTab
        @Namespace private var indicatorAnimation
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        var body: some View {
            HStack(spacing: 0) {
                ForEach(LibraryTab.allCases) { tab in
                    Button {
                        guard selection != tab else { return }
                        Haptics.selection()
                        withAnimation(DesignSystem.Motion.spring) {
                            selection = tab
                        }
                    } label: {
                        VStack(spacing: 2) {
                            ZStack {
                                if selection == tab {
                                    Capsule()
                                        .fill(DesignSystem.AppColors.accent.opacity(0.18))
                                        .frame(width: 48, height: 30)
                                        .shadow(color: DesignSystem.AppColors.accent.opacity(0.28), radius: 12)
                                        .matchedGeometryEffect(id: "tab-indicator", in: indicatorAnimation)
                                }
                                AppIconView(
                                    icon: tab.icon,
                                    size: .tab,
                                    weight: selection == tab ? .semibold : .regular,
                                    isActive: selection == tab,
                                    color: selection == tab ? DesignSystem.AppColors.accent : .secondary
                                )
                                .symbolEffect(.bounce, value: selection == tab)
                            }
                            .frame(height: 32)
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(selection == tab ? DesignSystem.AppColors.accent : .secondary)
                        }
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityLabel(tab.rawValue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .modifier(LiquidGlassCapsuleModifier())
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    struct LibrarySectionPicker: View {
        @Binding var selection: LibrarySection
        @Namespace private var animation
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        var body: some View {
            HStack(spacing: 4) {
                ForEach(LibrarySection.allCases) { section in
                    Button {
                        withAnimation(DesignSystem.Motion.spring) {
                            selection = section
                        }
                    } label: {
                        Text(section.rawValue)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(selection == section ? DesignSystem.AppColors.accentContrastText : DesignSystem.AppColors.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background {
                                if selection == section {
                                    Capsule()
                                        .fill(DesignSystem.AppColors.accent)
                                        .matchedGeometryEffect(id: "library-section", in: animation)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            .padding(4)
            .modifier(LiquidGlassCapsuleModifier())
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    struct TrackRow: View {
        let track: Track
        let isCurrent: Bool
        var isPlaying = false
        var isOffline = false
        var titleText: Text? = nil
        var trailingMenu: AnyView? = nil
        var actionAccessibilityLabel: String? = nil
        let action: () -> Void

        var body: some View {
            HStack(spacing: DesignSystem.AppSpacing.s8) {
                Button(action: action) {
                    HStack(spacing: 12) {
                        DesignSystem.ArtworkView(
                            data: track.artworkData,
                            size: 52,
                            placeholderKey: track.albumTitle,
                            cornerRadius: 12
                        )
                        .overlay(alignment: .bottomTrailing) {
                            if isCurrent && isPlaying {
                                EqualizerIndicator(isAnimating: true)
                                    .padding(3)
                                    .background(.black.opacity(0.72), in: Capsule())
                                    .offset(x: 4, y: 4)
                            }
                        }
                        VStack(alignment: .leading, spacing: DesignSystem.AppSpacing.s4) {
                            Group {
                                if let titleText {
                                    titleText
                                } else {
                                    Text(track.title)
                                }
                            }
                            .font(DesignSystem.headline)
                            .foregroundStyle(isCurrent && isPlaying ? DesignSystem.AppColors.accent : DesignSystem.AppColors.primaryText)
                            .lineLimit(1)
                            Text("\(track.artist) · \(track.albumTitle)")
                                .font(DesignSystem.subhead)
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if track.duration > 0 {
                            Text(Self.formatDuration(track.duration))
                                .font(.system(.caption, design: .rounded).monospacedDigit())
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                                .padding(.trailing, 2)
                        }
                        if isOffline && !track.isAvailableOffline {
                            AppIconView(icon: .offline, size: .row)
                                .frame(width: 32, height: 44)
                                .accessibilityLabel("Unavailable offline")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 68, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .accessibilityLabel(
                    actionAccessibilityLabel
                        ?? (isOffline && !track.isAvailableOffline
                            ? "Play \(track.title), unavailable offline"
                            : "Play \(track.title)")
                )
                if let trailingMenu {
                    trailingMenu
                        .frame(width: 44, height: 44)
                }
            }
            .frame(height: 68)
            .opacity(isOffline && !track.isAvailableOffline ? 0.4 : 1)
            .animation(DesignSystem.Motion.spring, value: isCurrent && isPlaying)
            .contentShape(Rectangle())
        }

        private static func formatDuration(_ seconds: Double) -> String {
            let total = max(Int(seconds), 0)
            return String(format: "%d:%02d", total / 60, total % 60)
        }
    }

    private struct EqualizerIndicator: View {
        let isAnimating: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            TimelineView(.animation(minimumInterval: 1 / 12, paused: !isAnimating || reduceMotion)) { timeline in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<3) { index in
                        let time = timeline.date.timeIntervalSinceReferenceDate * 7 + Double(index) * 1.8
                        Capsule()
                            .fill(DesignSystem.AppColors.accent)
                            .frame(width: 2.5, height: barHeight(at: time, index: index))
                    }
                }
                .frame(width: 12, height: 14, alignment: .center)
            }
            .accessibilityHidden(true)
        }

        private func barHeight(at time: TimeInterval, index: Int) -> CGFloat {
            guard isAnimating && !reduceMotion else { return 7 }
            let wave = (sin(time + Double(index) * 1.1) + 1) / 2
            return 4 + CGFloat(wave) * 10
        }
    }
}
