import SwiftUI

struct DashboardView: View {
    @StateObject private var store = DashboardStore()
    @State private var appeared = false

    private let modelColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    private let categoryColumns = [
        GridItem(.adaptive(minimum: 220), spacing: 12),
    ]

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 276, max: 310)
        } detail: {
            detail
        }
        .tint(DashboardPalette.accent)
        .font(.custom("Avenir Next", size: 13))
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                QuotaRing(
                    remaining: store.quota?.remainingPercent ?? 0,
                    diameter: 126
                )
                VStack(spacing: 3) {
                    Text("Сброс \(DashboardFormat.reset(store.quota?.primaryResetAt))")
                        .font(.custom("Avenir Next Demi Bold", size: 12))
                    Text(DashboardFormat.remaining(store.quota?.primaryResetAt))
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 22)
            .padding(.bottom, 18)

            Picker("Режим", selection: $store.rankingMode) {
                ForEach(RankingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            List(selection: $store.selectedModelName) {
                Section("МОДЕЛИ") {
                    ForEach(store.sortedModels) { model in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(color(for: model))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.custom("Avenir Next Demi Bold", size: 12))
                                    .lineLimit(1)
                                Text("\(model.score(for: store.rankingMode))/100 · \(model.confidence)% уверенность")
                                    .font(.custom("Avenir Next", size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(Optional(model.name))
                    }
                }
            }
            .listStyle(.sidebar)

            HStack {
                Circle()
                    .fill(DashboardPalette.accent)
                    .frame(width: 7, height: 7)
                Text("Данные обновлены \(DashboardFormat.updated(store.report?.generatedAt))")
                    .font(.custom("Avenir Next", size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.runAnalyzer()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Обновить аналитику")
            }
            .padding(14)
        }
        .navigationTitle("Codex Quota")
    }

    private var detail: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DashboardPalette.accent.opacity(0.08),
                    Color.clear,
                    DashboardPalette.blue.opacity(0.04),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    overview
                    recommendation
                    modelSection
                    categorySection
                    feedbackSection
                }
                .padding(26)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ЭФФЕКТИВНОСТЬ CODEX")
                    .font(.custom("Avenir Next Demi Bold", size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DashboardPalette.accent)
                Text("Как модели справляются с твоими задачами")
                    .font(.custom("Avenir Next Demi Bold", size: 28))
            }
            Spacer()
            Text("30 ДНЕЙ")
                .font(.custom("Avenir Next Demi Bold", size: 10))
                .tracking(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private var overview: some View {
        HStack(spacing: 12) {
            MetricTile(
                label: "Недельный запас",
                value: "\(store.quota?.remainingPercent ?? 0)%",
                detail: "\(100 - (store.quota?.remainingPercent ?? 0))% использовано"
            )
            MetricTile(
                label: "Следующий сброс",
                value: DashboardFormat.reset(store.quota?.primaryResetAt),
                detail: DashboardFormat.remaining(store.quota?.primaryResetAt),
                tint: DashboardPalette.blue
            )
            MetricTile(
                label: "Ручные сбросы",
                value: "\(store.quota?.resetCreditCount ?? 0)",
                detail: "доступно сейчас",
                tint: DashboardPalette.amber
            )
        }
    }

    @ViewBuilder
    private var recommendation: some View {
        if let model = store.recommendedModel {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ЛУЧШИЙ ВЫБОР · \(store.rankingMode.rawValue.uppercased())")
                        .font(.custom("Avenir Next Demi Bold", size: 9))
                        .tracking(1)
                        .foregroundStyle(Color.white.opacity(0.62))
                    Text(model.name)
                        .font(.custom("Avenir Next Demi Bold", size: 25))
                        .foregroundStyle(.white)
                    Text("\(model.tasks) задач · \(model.confidence)% уверенность")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                Spacer()
                recommendationMetric(
                    "Результат",
                    model.outcomeScore ?? model.score
                )
                recommendationMetric(
                    "Экономия",
                    model.efficiencyScore ?? 0
                )
                recommendationMetric(
                    "Скорость",
                    model.speedScore ?? 0
                )
                VStack(alignment: .trailing, spacing: 3) {
                    Text(DashboardFormat.tokens(model.tokensPerAcceptedResult))
                        .font(.custom("Avenir Next Demi Bold", size: 18))
                        .foregroundStyle(.white)
                    Text("токенов на принятый результат")
                        .font(.custom("Avenir Next", size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .padding(21)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.16, blue: 0.13),
                        Color(red: 0.12, green: 0.29, blue: 0.23),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 22)
            )
            .shadow(color: DashboardPalette.accent.opacity(0.17), radius: 20, y: 10)
        }
    }

    private func recommendationMetric(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.custom("Avenir Next Demi Bold", size: 22))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.custom("Avenir Next", size: 9))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(minWidth: 58)
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                "Сравнение моделей",
                "Рейтинг меняется вместе с выбранным режимом"
            )
            LazyVGrid(columns: modelColumns, spacing: 14) {
                ForEach(store.sortedModels) { model in
                    ModelAnalyticsCard(
                        model: model,
                        mode: store.rankingMode,
                        selected: model.name == store.selectedModel?.name
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectedModelName = model.name
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        let categories = store.report?.categoryRecommendations ?? []
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(
                    "Лучшие модели по типу задачи",
                    "Стоимость считается по всей цепочке переделок"
                )
                LazyVGrid(columns: categoryColumns, spacing: 12) {
                    ForEach(categories) { item in
                        CategoryCard(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if let latest = store.report?.latestUnrated {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ОЦЕНИТЬ ПОСЛЕДНИЙ РЕЗУЛЬТАТ · \(latest.model)")
                        .font(.custom("Avenir Next Demi Bold", size: 9))
                        .tracking(0.8)
                        .foregroundStyle(DashboardPalette.accent)
                    Text(latest.promptPreview ?? "Последняя выполненная задача")
                        .font(.custom("Avenir Next Demi Bold", size: 13))
                        .lineLimit(2)
                    if let feedbackMessage = store.feedbackMessage {
                        Text(feedbackMessage)
                            .font(.custom("Avenir Next", size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Нужна переделка") {
                    store.submitFeedback("rework")
                }
                .buttonStyle(.bordered)
                Button("Подошло") {
                    store.submitFeedback("good")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            }
        }
    }

    private func sectionTitle(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.custom("Avenir Next Demi Bold", size: 19))
            Spacer()
            Text(detail)
                .font(.custom("Avenir Next", size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func color(for model: ModelQuality) -> Color {
        if model.confidence < 25 { return .secondary }
        if model.score(for: store.rankingMode) >= 80 {
            return DashboardPalette.accent
        }
        if model.score(for: store.rankingMode) >= 65 {
            return DashboardPalette.blue
        }
        return DashboardPalette.amber
    }
}
