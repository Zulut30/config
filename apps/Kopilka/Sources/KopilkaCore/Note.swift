import Foundation

public struct Note: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var text: String
    public var comment: String
    public var tags: [String]
    public var links: [String]
    public var source: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var isArchived: Bool
    public var isDeleted: Bool

    public init(text: String, source: String = "Вручную", links: [String] = [], comment: String = "") {
        id = UUID()
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.comment = comment
        self.source = source
        self.links = LinkInfo.links(in: text, additional: links)
        let firstLine = self.text.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? "Новая заметка"
        if let repo = self.links.compactMap({ LinkInfo.repository($0) }).first {
            title = repo
            tags = ["Репозиторий"]
        } else {
            title = String(firstLine.prefix(100))
            tags = self.links.isEmpty ? ["Идея"] : ["Прочитать"]
        }
        createdAt = Date()
        updatedAt = createdAt
        isPinned = false
        isArchived = false
        isDeleted = false
    }

    public func matches(_ query: String) -> Bool {
        let fields = ([title, text, comment, source] + tags + links).joined(separator: "\n")
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
            fields.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    public var markdown: String {
        var result = "# \(title)\n\n\(text)\n"
        for link in links where !text.contains(link) { result += "\n\(link)\n" }
        if !comment.isEmpty { result += "\n## Мой комментарий\n\n\(comment)\n" }
        result += "\n---\nИсточник: \(source)\nДата: \(createdAt.ISO8601Format())\n"
        if !tags.isEmpty { result += "Теги: \(tags.map { "#" + $0 }.joined(separator: " "))\n" }
        return result
    }
}

public enum LinkInfo {
    public static func safeURL(_ string: String) -> URL? {
        guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    public static func links(in text: String, additional: [String] = []) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let found = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { $0.url?.absoluteString } ?? []
        var seen = Set<String>()
        return (found + additional).compactMap { raw in
            guard let url = safeURL(raw) else { return nil }
            let value = url.absoluteString
            return seen.insert(value).inserted ? value : nil
        }
    }

    public static func repository(_ string: String) -> String? {
        guard let url = safeURL(string), ["github.com", "www.github.com"].contains(url.host?.lowercased() ?? "") else { return nil }
        let pieces = url.path.split(separator: "/")
        guard pieces.count >= 2, !["settings", "login", "features", "topics", "collections", "marketplace", "orgs", "users", "search"].contains(String(pieces[0]).lowercased()) else { return nil }
        var repo = String(pieces[1])
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard !repo.isEmpty else { return nil }
        return "\(pieces[0])/\(repo)"
    }

    public static func tags(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").compactMap {
            let tag = $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            return !tag.isEmpty && seen.insert(tag.lowercased()).inserted ? tag : nil
        }
    }
}
