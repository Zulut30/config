import SwiftUI

struct DashboardView: View {
    @StateObject private var store = DashboardStore()
    @State private var appeared = false

    private let modelColumns = [
        GridItem(.adaptive(minimum: 390), spacing: 20),
    ]

    private let categoryColumns = [
        GridItem(.adaptive(minimum: 250), spacing: 16),
    ]

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 350)
        } detail: {
            detail
        }
        .tint(DashboardPalette.accent)
        .font(.custom("Avenir Next", size: 13))
        .environment(\.controlSize, .regular)
        .fontDesign(.rounded)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.isRefreshing {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Обновляю")
                            .font(.custom("Avenir Next Medium", size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        store.runAnalyzer()
                    } label: {
                        Label("Обновить", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DashboardPalette.accent,
                                    Color(red: 0.08, green: 0.30, blue: 0.23),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("CQ")
                        .font(.custom("Avenir Next Demi Bold", size: 12))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Quota")
                        .font(.custom("Avenir Next Demi Bold", size: 16))
                    Text("Личная эффективность моделей")
                        .font(.custom("Avenir Next", size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 7) {
                Text("КАК ВЫБИРАТЬ МОДЕЛЬ")
                    .font(.custom("Avenir Next Demi Bold", size: 9))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Picker("Режим", selection: $store.rankingMode) {
                    ForEach(RankingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)

            List(selection: $store.selectedModelName) {
                Section("МОДЕЛИ") {
                    ForEach(store.sortedModels) { model in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(color(for: model))
                                .frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.name)
                                    .font(.custom("Avenir Next Demi Bold", size: 13))
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text("\(model.score(for: store.rankingMode))/100")
                                    Text("·")
                                    Text("\(model.confidence)% уверенность")
                                }
                                .font(.custom("Avenir Next", size: 10))
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.name == store.recommendedModel?.name {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(DashboardPalette.accent)
                                    .help("Рекомендуемая модель")
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(Optional(model.name))
                    }
                }
            }
            .listStyle(.sidebar)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(DashboardPalette.accent)
                        .frame(width: 7, height: 7)
                    Text("Аналитика работает локально")
                        .font(.custom("Avenir Next Demi Bold", size: 10))
                }
                Text("Обновлено \(DashboardFormat.updated(store.report?.generatedAt)) · ⌘R для пересчёта")
                    .font(.custom("Avenir Next", size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
                VStack(alignment: .leading, spacing: 20) {
                    header
                    heroRow
                    feedbackSection
                    modelSection
                    categorySection
                    methodology
                }
                .padding(32)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ЭФФЕКТИВНОСТЬ CODEX")
                    .font(.custom("Avenir Next Demi Bold", size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DashboardPalette.accent)
                Text("Меньше токенов на хороший результат")
                    .font(.custom("Avenir Next Demi Bold", size: 30))
                Text("Сравнение учитывает переделки, сложность задачи и твою оценку.")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("30 ДНЕЙ")
                    .font(.custom("Avenir Next Demi Bold", size: 10))
                    .tracking(1)
                Text("Spark исключён")
                    .font(.custom("Avenir Next", size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var heroRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                quotaCard
                    .frame(width: 304)
                recommendationCard
                    .frame(minWidth: 560)
            }
            VStack(spacing: 20) {
                quotaCard
                recommendationCard
            }
        }
    }

    private var quotaCard: some View {
        HStack(spacing: 17) {
            QuotaRing(
                remaining: store.quota?.remainingPercent ?? 0,
                diameter: 104
            )
            VStack(alignment: .leading, spacing: 7) {
                Text("НЕДЕЛЬНЫЙ ЛИМИТ")
                    .font(.custom("Avenir Next Demi Bold", size: 9))
                    .tracking(0.9)
                    .foregroundStyle(DashboardPalette.accent)
                Text(DashboardFormat.reset(store.quota?.primaryResetAt))
                    .font(.custom("Avenir Next Demi Bold", size: 17))
                Text(DashboardFormat.remaining(store.quota?.primaryResetAt))
                    .font(.custom("Avenir Next", size: 11))
                    .foregroundStyle(.secondary)
                Label(
                    "\(store.quota?.resetCreditCount ?? 0) ручной сброс",
                    systemImage: "arrow.counterclockwise.circle"
                )
                .font(.custom("Avenir Next Medium", size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var recommendationCard: some View {
        if let model = store.recommendedModel {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ЛУЧШИЙ ВЫБОР · \(store.rankingMode.rawValue.uppercased())")
                        .font(.custom("Avenir Next Demi Bold", size: 9))
                        .tracking(1)
                        .foregroundStyle(Color.white.opacity(0.62))
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(model.name)
                            .font(.custom("Avenir Next Demi Bold", size: 25))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text("\(model.score(for: store.rankingMode))/100")
                            .font(.custom("Avenir Next Demi Bold", size: 14))
                            .foregroundStyle(Color.white.opacity(0.74))
                    }
                    Text("Цена принятого результата: \(DashboardFormat.tokens(model.tokensPerAcceptedResult)) токенов")
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundStyle(Color.white.opacity(0.66))
                }
                .frame(minWidth: 210, idealWidth: 230, maxWidth: 260, alignment: .leading)
                .layoutPriority(1)
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
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(model.confidence)%")
                        .font(.custom("Avenir Next Demi Bold", size: 20))
                        .foregroundStyle(.white)
                    Text("уверенность")
                        .font(.custom("Avenir Next", size: 9))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Text("\(model.tasks) задач")
                        .font(.custom("Avenir Next Medium", size: 10))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
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
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text("Собираю рекомендацию")
                    .font(.custom("Avenir Next Demi Bold", size: 20))
                Text("Нужно несколько сопоставимых задач с реакцией пользователя.")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(
                LinearGradient(
                    colors: [
                        DashboardPalette.accent.opacity(0.16),
                        Color.white.opacity(0.045),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(DashboardPalette.accent.opacity(0.22), lineWidth: 1)
            }
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
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle(
                "Сравнение моделей",
                "Нажми на карточку, чтобы закрепить модель в боковой панели"
            )
            LazyVGrid(columns: modelColumns, spacing: 20) {
                ForEach(store.sortedModels) { model in
                    ModelAnalyticsCard(
                        model: model,
                        mode: store.rankingMode,
                        selected: model.name == store.selectedModel?.name
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            store.selectedModelName = model.name
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        let categories = store.report?.categoryRecommendations ?? []
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle(
                    "Лучшие модели по типу задачи",
                    "Сравниваются только похожие задачи"
                )
                LazyVGrid(columns: categoryColumns, spacing: 16) {
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
                ZStack {
                    Circle()
                        .fill(DashboardPalette.accent.opacity(0.13))
                    Image(systemName: "checkmark.message")
                        .foregroundStyle(DashboardPalette.accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text("ПОМОГИ УТОЧНИТЬ РЕЙТИНГ · \(latest.model)")
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
            .padding(17)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(DashboardPalette.accent.opacity(0.15), lineWidth: 1)
            }
        }
    }

    private var methodology: some View {
        HStack(spacing: 14) {
            Image(systemName: "info.circle")
                .font(.system(size: 20))
                .foregroundStyle(DashboardPalette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Как считается рейтинг")
                    .font(.custom("Avenir Next Demi Bold", size: 13))
                Text("60% качество · 25% экономность · 15% скорость. Расход и время сравниваются внутри похожих задач с поправкой на сложность; малая выборка приближает оценку к нейтральным 50 баллам.")
                    .font(.custom("Avenir Next", size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(15)
        .background(DashboardPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func sectionTitle(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.custom("Avenir Next Demi Bold", size: 20))
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
