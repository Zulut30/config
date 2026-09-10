import SwiftUI

enum DashboardPalette {
    static let accent = Color(red: 0.12, green: 0.56, blue: 0.41)
    static let accentSoft = Color(red: 0.85, green: 0.95, blue: 0.90)
    static let amber = Color(red: 0.83, green: 0.52, blue: 0.16)
    static let blue = Color(red: 0.27, green: 0.47, blue: 0.82)
    static let rose = Color(red: 0.73, green: 0.35, blue: 0.49)
}

struct QuotaRing: View {
    let remaining: Int
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.09), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, remaining))) / 100)
                .stroke(
                    DashboardPalette.accent,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(remaining)%")
                    .font(.custom("Avenir Next Demi Bold", size: diameter * 0.25))
                    .monospacedDigit()
                Text("ОСТАЛОСЬ")
                    .font(.custom("Avenir Next Demi Bold", size: 9))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Осталось \(remaining) процентов недельного лимита")
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let detail: String
    var tint: Color = DashboardPalette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label.uppercased())
                    .font(.custom("Avenir Next Demi Bold", size: 10))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }
            Text(value)
                .font(.custom("Avenir Next Demi Bold", size: 24))
                .monospacedDigit()
            Text(detail)
                .font(.custom("Avenir Next", size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

struct ScoreBar: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.custom("Avenir Next Medium", size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(value)")
                    .font(.custom("Avenir Next Demi Bold", size: 12))
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: geometry.size.width
                                * CGFloat(max(0, min(100, value))) / 100
                        )
                }
            }
            .frame(height: 6)
        }
    }
}

struct ModelAnalyticsCard: View {
    let model: ModelQuality
    let mode: RankingMode
    let selected: Bool

    private var scoreColor: Color {
        if model.confidence < 25 { return .secondary }
        if model.score(for: mode) >= 80 { return DashboardPalette.accent }
        if model.score(for: mode) >= 65 { return DashboardPalette.blue }
        return DashboardPalette.amber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.custom("Avenir Next Demi Bold", size: 17))
                        .lineLimit(1)
                    Text("\(model.tasks) задач · уверенность \(model.confidence)%")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(model.score(for: mode))")
                        .font(.custom("Avenir Next Demi Bold", size: 31))
                        .foregroundStyle(scoreColor)
                        .monospacedDigit()
                    Text("/100")
                        .font(.custom("Avenir Next Medium", size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            ScoreBar(
                label: "Качество результата",
                value: model.outcomeScore ?? model.score,
                tint: DashboardPalette.accent
            )
            ScoreBar(
                label: "Экономичность",
                value: model.efficiencyScore ?? 0,
                tint: DashboardPalette.amber
            )
            ScoreBar(
                label: "Скорость",
                value: model.speedScore ?? 0,
                tint: DashboardPalette.blue
            )

            Divider()

            HStack(spacing: 18) {
                CompactValue(
                    label: "Принятый результат",
                    value: DashboardFormat.tokens(model.tokensPerAcceptedResult)
                )
                CompactValue(
                    label: "С первой попытки",
                    value: model.firstPassRate.map { "\(Int($0))%" } ?? "Нет данных"
                )
                CompactValue(
                    label: "Переделки",
                    value: model.reworkTokenShare.map { "\(Int($0))%" } ?? "Нет данных"
                )
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    selected ? DashboardPalette.accent : .primary.opacity(0.07),
                    lineWidth: selected ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(selected ? 0.08 : 0.03), radius: 14, y: 7)
    }
}

struct CompactValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.custom("Avenir Next Demi Bold", size: 13))
                .monospacedDigit()
            Text(label)
                .font(.custom("Avenir Next", size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct CategoryCard: View {
    let item: CategoryRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(item.label.uppercased())
                .font(.custom("Avenir Next Demi Bold", size: 9))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(item.model)
                .font(.custom("Avenir Next Demi Bold", size: 15))
                .lineLimit(1)
            HStack {
                Label("\(item.score)/100", systemImage: "chart.line.uptrend.xyaxis")
                Spacer()
                Text(DashboardFormat.tokens(item.acceptedCost))
            }
            .font(.custom("Avenir Next Medium", size: 11))
            .foregroundStyle(DashboardPalette.accent)
            Text("\(item.confidence)% уверенность · \(item.tasks) задач")
                .font(.custom("Avenir Next", size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
