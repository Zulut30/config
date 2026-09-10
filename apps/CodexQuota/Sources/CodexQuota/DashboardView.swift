import SwiftUI

final class DashboardState: ObservableObject {
    @Published var snapshot: CodexSnapshot?
}

private enum DashboardPalette {
    static let night = Color(red: 0.035, green: 0.065, blue: 0.105)
    static let surface = Color(red: 0.075, green: 0.125, blue: 0.185)
    static let surfaceRaised = Color(red: 0.105, green: 0.175, blue: 0.245)
    static let mint = Color(red: 0.31, green: 0.92, blue: 0.71)
    static let blue = Color(red: 0.34, green: 0.66, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.31)
    static let coral = Color(red: 1.0, green: 0.44, blue: 0.37)
    static let muted = Color.white.opacity(0.56)
}

private struct DashboardModel: Identifiable {
    let id: String
    let name: String
    let share: Int
    let outputTokens: Int
    let completedTasks: Int
    let activeSeconds: Int

    var tokensPerTask: Int {
        guard completedTasks > 0 else { return 0 }
        return outputTokens / completedTasks
    }

    var accent: Color {
        switch id.lowercased() {
        case "gpt-6-astra": return DashboardPalette.amber
        case "gpt-5.6-terra": return DashboardPalette.mint
        case "gpt-5.6-luna": return DashboardPalette.blue
        default: return DashboardPalette.coral
        }
    }
}

private struct DashboardLimit: Identifiable {
    let id: String
    let name: String
    let usedPercent: Int
    let resetDate: Date?
}

private struct DashboardMetrics {
    let remaining: Int
    let resetDate: Date?
    let resetCredits: Int
    let models: [DashboardModel]
    let limits: [DashboardLimit]
    let totalTasks: Int
    let totalOutputTokens: Int

    init(snapshot: CodexSnapshot) {
        let used = snapshot.primary.weekly?.usedPercent ?? 0
        remaining = min(100, max(0, 100 - used))
        resetDate = snapshot.primary.weekly?.resetDate
        resetCredits = snapshot.resetCreditCount

        let workStats = (snapshot.taskStats ?? []).filter { !$0.model.lowercased().contains("spark") }
        let taskCount = workStats.reduce(0) { $0 + $1.completedTasks }
        let generatedTokens = workStats.reduce(0) { $0 + $1.outputTokens }
        let dashboardModels = workStats.map { stat in
            DashboardModel(
                id: stat.model,
                name: Self.friendlyName(stat.model),
                share: generatedTokens > 0
                    ? Int((Double(stat.outputTokens) / Double(generatedTokens) * 100).rounded())
                    : 0,
                outputTokens: stat.outputTokens,
                completedTasks: stat.completedTasks,
                activeSeconds: stat.activeSeconds
            )
        }
        .sorted { $0.outputTokens > $1.outputTokens }
        totalTasks = taskCount
        totalOutputTokens = generatedTokens
        models = dashboardModels

        limits = snapshot.models.compactMap { model in
            guard !model.name.lowercased().contains("spark"), let weekly = model.weekly else { return nil }
            return DashboardLimit(
                id: model.id,
                name: Self.friendlyName(model.name),
                usedPercent: weekly.usedPercent,
                resetDate: weekly.resetDate
            )
        }
    }

    var astra: DashboardModel? {
        models.first { $0.id.lowercased() == "gpt-6-astra" }
    }

    var averageTokensPerTask: Int {
        guard totalTasks > 0 else { return 0 }
        return totalOutputTokens / totalTasks
    }

    var astraCostRatio: Double? {
        guard let astra, astra.tokensPerTask > 0, averageTokensPerTask > 0 else { return nil }
        return Double(astra.tokensPerTask) / Double(averageTokensPerTask)
    }

    var astraVerdictTitle: String {
        guard let ratio = astraCostRatio else { return "Astra: собираем данные" }
        if ratio >= 1.5 { return "Astra заметно дороже средней" }
        if ratio >= 1.15 { return "Astra немного дороже средней" }
        if ratio >= 0.85 { return "Astra близка к среднему расходу" }
        return "Astra экономнее среднего" 
    }

    var astraVerdictDetail: String {
        guard let astra = astra, let ratio = astraCostRatio else {
            return "После нескольких завершённых задач появится сравнение токенов на одну задачу."
        }
        return compactTokens(astra.tokensPerTask)
            + " токенов на задачу, это "
            + String(format: "%.1f", ratio)
            + "x от твоего среднего."
    }

    var astraRecommendation: String {
        guard let ratio = astraCostRatio else {
            return "Выгоду оценивают не только по токенам: важен результат задачи."
        }
        if ratio >= 1.5 {
            return "Оставляй Astra для архитектуры, сложного дебага и больших изменений. Рутину выгоднее отдавать Terra или Luna."
        }
        if ratio >= 1.15 {
            return "Цена Astra немного выше средней. Она оправдана, когда качество ответа экономит тебе время на переделках."
        }
        return "По расходу Astra не выбивается из твоего среднего. Если задачи решаются с первой попытки, её использование выглядит оправданным."
    }

    private static func friendlyName(_ name: String) -> String {
        switch name.lowercased() {
        case "gpt-6-astra": return "Astra"
        case "gpt-5.6-terra": return "Terra"
        case "gpt-5.6-luna": return "Luna"
        case "gpt-5.3-codex-spark": return "Spark"
        default: return name
        }
    }
}

struct QuotaDashboard: View {
    @ObservedObject var state: DashboardState
    let refreshAction: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DashboardPalette.night, Color(red: 0.03, green: 0.11, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    dashboardHeader

                    if let snapshot = state.snapshot {
                        dashboardContent(metrics: DashboardMetrics(snapshot: snapshot), snapshot: snapshot)
                    } else {
                        loadingState
                    }
                }
                .padding(28)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }

    private var dashboardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CODEX QUOTA")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2.1)
                    .foregroundStyle(DashboardPalette.mint)
                Text("Лимиты и цена моделей")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button(action: refreshAction) {
                Label("Обновить", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .tint(DashboardPalette.mint)
        }
    }

    private func dashboardContent(metrics: DashboardMetrics, snapshot: CodexSnapshot) -> some View {
        VStack(spacing: 18) {
            hero(metrics)
            astraInsight(metrics)
            modelBreakdown(metrics)
            limitSection(metrics, snapshot: snapshot)
            Text("Нагрузка считается по сгенерированным токенам за последние 7 дней. Это измеряет стоимость, но не может автоматически оценить качество результата.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hero(_ metrics: DashboardMetrics) -> some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 4) {
                Text("НЕДЕЛЬНЫЙ ЗАПАС")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color.white.opacity(0.68))
                Text("\(metrics.remaining)%")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("осталось до следующего сброса")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
                Meter(value: metrics.remaining, color: DashboardPalette.mint)
                    .frame(width: 290, height: 10)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 13) {
                HeroDetail(label: "Сброс", value: resetText(metrics.resetDate))
                HeroDetail(label: "Использовано", value: "\(100 - metrics.remaining)%")
                HeroDetail(label: "Ручные сбросы", value: "\(metrics.resetCredits)")
            }
            .frame(minWidth: 190, alignment: .leading)
        }
        .padding(26)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.31, blue: 0.33), Color(red: 0.08, green: 0.15, blue: 0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.12)))
    }

    private func astraInsight(_ metrics: DashboardMetrics) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(DashboardPalette.amber.opacity(0.18))
                Text("A")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardPalette.amber)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 7) {
                Text("ASTRA: ВЫГОДНО ЛИ ИСПОЛЬЗУЕТСЯ?")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(DashboardPalette.amber)
                Text(metrics.astraVerdictTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(metrics.astraVerdictDetail)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                Text(metrics.astraRecommendation)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(DashboardPalette.surfaceRaised.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DashboardPalette.amber.opacity(0.22)))
    }

    private func modelBreakdown(_ metrics: DashboardMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "КУДА УХОДЯТ РЕСУРСЫ", subtitle: "Доля генерации без отдельной шкалы Spark")
            if metrics.models.isEmpty {
                Text("Данные о завершённых задачах пока не накопились.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardPalette.muted)
                    .padding(.vertical, 12)
            } else {
                ForEach(metrics.models) { model in
                    ModelUsageRow(model: model)
                }
            }
        }
        .padding(20)
        .background(DashboardPalette.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func limitSection(_ metrics: DashboardMetrics, snapshot: CodexSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "ЛИМИТЫ", subtitle: "Обновлено \(timeText(snapshot.fetchedAt))")
            ForEach(metrics.limits) { limit in
                HStack(spacing: 12) {
                    Text(limit.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(limit.usedPercent)% использовано")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardPalette.mint)
                    Text("Сброс \(resetText(limit.resetDate))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DashboardPalette.muted)
                }
                if limit.id != metrics.limits.last?.id {
                    Divider().overlay(Color.white.opacity(0.1))
                }
            }
        }
        .padding(20)
        .background(DashboardPalette.surface.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(DashboardPalette.mint)
            Text("Получаем текущие лимиты Codex...")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardPalette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 440)
    }
}

private struct HeroDetail: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Color.white.opacity(0.56))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(DashboardPalette.mint)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardPalette.muted)
        }
    }
}

private struct ModelUsageRow: View {
    let model: DashboardModel

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(model.accent.opacity(0.2))
                    Text(String(model.name.prefix(1)))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(model.accent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(model.completedTasks) задач  |  \(durationText(model.activeSeconds))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DashboardPalette.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(model.share)%")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(model.accent)
                    Text("доля нагрузки")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardPalette.muted)
                }
            }
            Meter(value: model.share, color: model.accent)
                .frame(height: 7)
            HStack {
                Text("\(compactTokens(model.outputTokens)) токенов")
                Spacer()
                Text("\(compactTokens(model.tokensPerTask)) на задачу")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.72))
        }
        .padding(15)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct Meter: View {
    let value: Int
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.72), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * CGFloat(min(100, max(0, value))) / 100)
            }
        }
    }
}

private func compactTokens(_ tokens: Int) -> String {
    if tokens >= 1_000_000 { return String(format: "%.1f млн", Double(tokens) / 1_000_000) }
    if tokens >= 1_000 { return String(format: "%.1f тыс.", Double(tokens) / 1_000) }
    return "\(tokens)"
}

private func durationText(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    return hours > 0 ? "\(hours) ч. \(minutes) мин." : "\(minutes) мин."
}

private func resetText(_ date: Date?) -> String {
    guard let date else { return "неизвестен" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func timeText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
