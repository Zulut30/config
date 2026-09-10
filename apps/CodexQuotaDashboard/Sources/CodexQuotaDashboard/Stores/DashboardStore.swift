import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var quota: QuotaSnapshot?
    @Published private(set) var report: QualityReport?
    @Published var rankingMode: RankingMode = .balance
    @Published var selectedModelName: String?
    @Published private(set) var feedbackMessage: String?

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var refreshTimer: Timer?

    private var cacheDirectory: URL {
        home
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("CodexQuota")
    }

    private var quotaURL: URL {
        cacheDirectory.appendingPathComponent("status.json")
    }

    private var qualityURL: URL {
        cacheDirectory.appendingPathComponent("model-quality.json")
    }

    private var feedbackURL: URL {
        cacheDirectory.appendingPathComponent("model-feedback.json")
    }

    private var analyzerURL: URL {
        home
            .appendingPathComponent(".hammerspoon")
            .appendingPathComponent("codex_model_quality.py")
    }

    init() {
        reload()
        runAnalyzer()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 15,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    var sortedModels: [ModelQuality] {
        (report?.models ?? []).sorted {
            let left = $0.score(for: rankingMode)
            let right = $1.score(for: rankingMode)
            if left == right {
                return $0.confidence > $1.confidence
            }
            return left > right
        }
    }

    var recommendedModel: ModelQuality? {
        sortedModels.first(where: { $0.confidence >= 25 })
    }

    var selectedModel: ModelQuality? {
        guard let selectedModelName else { return recommendedModel }
        return report?.models.first(where: { $0.name == selectedModelName })
    }

    func reload() {
        quota = decode(QuotaSnapshot.self, from: quotaURL)
        report = decode(QualityReport.self, from: qualityURL)
        if selectedModelName == nil {
            selectedModelName = recommendedModel?.name
        }
    }

    func runAnalyzer() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [analyzerURL.path]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.reload()
            }
        }
        try? process.run()
    }

    func submitFeedback(_ verdict: String) {
        guard verdict == "good" || verdict == "rework",
              let latest = report?.latestUnrated
        else {
            return
        }

        var file = decode(FeedbackFile.self, from: feedbackURL)
            ?? FeedbackFile(version: 1, records: [])
        let record = FeedbackRecord(
            turnId: latest.turnId,
            model: latest.model,
            verdict: verdict,
            timestamp: Date().timeIntervalSince1970
        )

        if let index = file.records.firstIndex(where: { $0.turnId == latest.turnId }) {
            file.records[index] = record
        } else {
            file.records.append(record)
        }

        do {
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(file)
            try data.write(to: feedbackURL, options: .atomic)
            feedbackMessage = verdict == "good"
                ? "Результат отмечен как принятый"
                : "Переделка добавлена в стоимость задачи"
            runAnalyzer()
        } catch {
            feedbackMessage = "Не удалось сохранить оценку"
        }
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from url: URL
    ) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
