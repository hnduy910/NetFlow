import SwiftUI

@MainActor
enum AppChrome {
    static var pagePadding: CGFloat {
        UIScreen.main.bounds.width <= 390 ? 10 : 14
    }

    static var cardPadding: CGFloat {
        UIScreen.main.bounds.width <= 390 ? 12 : 16
    }

    static var spacing: CGFloat {
        UIScreen.main.bounds.width <= 390 ? 10 : 14
    }
}

extension View {
    func netFlowSectionTitle() -> some View {
        font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    func netFlowCard(cornerRadius: CGFloat = 18) -> some View {
        padding(AppChrome.cardPadding)
            .background(Color.white, in: RoundedRectangle(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.black.opacity(0.65), lineWidth: 1)
            )
    }

    func netFlowPageBackground() -> some View {
        background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}
