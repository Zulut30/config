import Foundation

enum RankingMode: String, CaseIterable, Identifiable {
    case balance = "Баланс"
    case quality = "Качество"
    case economy = "Экономия"
    case speed = "Скорость"

    var id: Self { self }
}

struct QuotaSnapshot: Decodable {
    let primaryResetAt: TimeInterval?
    let resetCreditCount: Int?
    let remainingPercent: Int?
    let updatedAt: TimeInterval?
}

struct QualityReport: Decodable {
    let generatedAt: TimeInterval?
    let periodDays: Int?
    let models: [ModelQuality]
    let categoryRecommendations: [CategoryRecommendation]?
    let latestUnrated: LatestUnrated?
}

struct ModelQuality: Decodable, Identifiable {
    var id: String { name }

    let name: String
    let tasks: Int
    let evaluatedTasks: Int?
    let acceptedResults: Int?
    let score: Int
    let confidence: Int
    let outcomeScore: Int?
    let efficiencyScore: Int?
    let speedScore: Int?
    let firstPassRate: Double?
    let acceptanceRate: Double?
    let completionRate: Double?
    let toolSuccessRate: Double?
    let validationRate: Double?
    let totalTokens: Double?
    let effectiveTokens: Double?
    let cachedInputTokens: Double?
    let tokensPerAcceptedResult: Double?
    let effectiveTokensPerAcceptedResult: Double?
    let secondsPerAcceptedResult: Double?
    let reworkTokenShare: Double?
    let normalizedTokenIndex: Double?
    let normalizedTimeIndex: Double?
    let tokenSavingsPercent: Double?
    let timeSavingsPercent: Double?

    func score(for mode: RankingMode) -> Int {
        switch mode {
        case .balance:
            return score
        case .quality:
            return outcomeScore ?? score
        case .economy:
            return efficiencyScore ?? score
        case .speed:
            return speedScore ?? score
        }
    }
}

struct CategoryRecommendation: Decodable, Identifiable {
    var id: String { category }

    let category: String
    let label: String
    let model: String
    let score: Int
    let confidence: Int
    let tasks: Int
    let acceptedCost: Double
}

struct LatestUnrated: Decodable {
    let turnId: String
    let model: String
    let startedAt: TimeInterval?
    let promptPreview: String?
}

struct FeedbackFile: Codable {
    var version: Int
    var records: [FeedbackRecord]
}

struct FeedbackRecord: Codable {
    var turnId: String
    var model: String
    var verdict: String
    var timestamp: TimeInterval
}
