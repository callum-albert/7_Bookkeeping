import SwiftUI

// MARK: - 设计令牌
enum Theme {
    static let brand = Color(red: 0.35, green: 0.36, blue: 0.98)
    static let brandSoft = Color(red: 0.55, green: 0.45, blue: 1.00)
    static let mint = Color(red: 0.24, green: 0.80, blue: 0.66)
    static let warm = Color(red: 1.00, green: 0.62, blue: 0.32)
    static let danger = Color(red: 0.98, green: 0.35, blue: 0.42)

    static let corner: CGFloat = 26
    static let cornerSmall: CGFloat = 18
}

// MARK: - 背景：柔和光晕，衬托液态玻璃
struct AppBackground: View {
    private var _scheme = Environment(\.colorScheme)
    private var scheme: ColorScheme { _scheme.wrappedValue }

    var body: some View {
        ZStack {
            baseGradient
            // 三个流动光斑，给玻璃提供折射质感
            GeometryReader { geo in
                ZStack {
                    blob(Theme.brandSoft.opacity(scheme == .dark ? 0.55 : 0.42),
                         size: geo.size.width * 0.95)
                        .offset(x: -geo.size.width * 0.28, y: -geo.size.height * 0.30)
                    blob(Theme.mint.opacity(scheme == .dark ? 0.34 : 0.34),
                         size: geo.size.width * 0.75)
                        .offset(x: geo.size.width * 0.34, y: -geo.size.height * 0.02)
                    blob(Theme.warm.opacity(scheme == .dark ? 0.26 : 0.30),
                         size: geo.size.width * 0.80)
                        .offset(x: -geo.size.width * 0.10, y: geo.size.height * 0.36)
                }
                .blur(radius: 70)
            }
        }
        .ignoresSafeArea()
    }

    private var baseGradient: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.09, green: 0.08, blue: 0.14)]
                : [Color(red: 0.98, green: 0.98, blue: 1.00), Color(red: 0.94, green: 0.95, blue: 1.00)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - 玻璃卡片
struct GlassCard<Content: View>: View {
    var corner: CGFloat = Theme.corner
    var padding: CGFloat = 18
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: corner))
    }

    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.28)) }
        return g
    }
}

// MARK: - 小标签
struct TagView: View {
    var text: String
    var symbol: String? = nil
    var tint: Color = Theme.brand

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: .capsule)
    }
}

// MARK: - 分类图标
struct CategoryBadge: View {
    var category: Category
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [category.tint.opacity(0.95), category.tint.opacity(0.66)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .circle
            )
            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.8).blendMode(.overlay))
            .shadow(color: category.tint.opacity(0.32), radius: 8, y: 4)
    }
}

// MARK: - 数字滚动金额
struct MoneyText: View {
    var cents: Int
    var size: CGFloat = 40
    var weight: Font.Weight = .semibold
    var showSymbol: Bool = true

    var body: some View {
        let text = showSymbol ? "¥" + cents.amountOnly : cents.amountOnly
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - 玻璃按钮样式（iOS 26+ 原生）
struct GlassProminentButton: ViewModifier {
    var tint: Color = Theme.brand
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
                    .blendMode(.overlay)
            )
            .shadow(color: tint.opacity(0.35), radius: 14, y: 8)
    }
}

extension View {
    func prominentGlassButton(tint: Color = Theme.brand) -> some View {
        modifier(GlassProminentButton(tint: tint))
    }
}
