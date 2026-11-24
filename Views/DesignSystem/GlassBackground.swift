import SwiftUI

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(DesignSystem.AppColors.backgroundSecondary, in: shape)
                .overlay(shape.stroke(DesignSystem.AppColors.border, lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(DesignSystem.AppColors.card), in: shape)
                .overlay(shape.stroke(DesignSystem.AppColors.border, lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(DesignSystem.AppColors.border, lineWidth: 1))
        }
    }
}

struct GlassCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(DesignSystem.AppColors.backgroundSecondary, in: Capsule())
                .overlay(Capsule().stroke(DesignSystem.AppColors.border, lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(DesignSystem.AppColors.card), in: Capsule())
                .overlay(Capsule().stroke(DesignSystem.AppColors.border, lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(DesignSystem.AppColors.border, lineWidth: 1))
        }
    }
}

struct LiquidGlassCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(DesignSystem.AppColors.backgroundSecondary, in: Capsule())
                .overlay(Capsule().stroke(DesignSystem.AppColors.border, lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(DesignSystem.AppColors.card), in: Capsule())
                .overlay(Capsule().stroke(DesignSystem.AppColors.border, lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(DesignSystem.AppColors.border, lineWidth: 1))
        }
    }
}

struct GlassCircleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(DesignSystem.AppColors.backgroundSecondary, in: Circle())
                .overlay(Circle().stroke(DesignSystem.AppColors.border, lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(DesignSystem.AppColors.card), in: Circle())
                .overlay(Circle().stroke(DesignSystem.AppColors.border, lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(DesignSystem.AppColors.border, lineWidth: 1))
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = DesignSystem.AppRadius.card) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func glassCapsule() -> some View {
        modifier(GlassCapsuleModifier())
    }

    func glassCircle() -> some View {
        modifier(GlassCircleModifier())
    }
}
