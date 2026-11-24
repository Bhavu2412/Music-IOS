import SwiftUI

struct AnimatedArtworkBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [
                        DesignSystem.AppColors.background,
                        DesignSystem.AppColors.backgroundSecondary
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [
                        DesignSystem.AppColors.accent.opacity(0.12),
                        DesignSystem.AppColors.accent.opacity(0)
                    ],
                    center: .top,
                    startRadius: 4,
                    endRadius: geometry.size.width * 0.9
                )
                .frame(height: geometry.size.height * 0.42)
                .accessibilityHidden(true)
            }
            .ignoresSafeArea()
        }
    }
}
