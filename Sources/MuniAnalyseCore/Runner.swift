import Foundation

public struct TextAnalysisTerm: Codable, Equatable, Sendable {
    public let term: String
    public let occurrences: Int

    public init(term: String, occurrences: Int) {
        self.term = term
        self.occurrences = occurrences
    }
}

public struct TextAnalysisReport: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let characterCount: Int
    public let nonWhitespaceCharacterCount: Int
    public let lineCount: Int
    public let paragraphCount: Int
    public let wordCount: Int
    public let uniqueWordCount: Int
    public let sentenceCount: Int
    public let topTerms: [TextAnalysisTerm]
    public let preview: String

    public init(
        generatedAt: String,
        characterCount: Int,
        nonWhitespaceCharacterCount: Int,
        lineCount: Int,
        paragraphCount: Int,
        wordCount: Int,
        uniqueWordCount: Int,
        sentenceCount: Int,
        topTerms: [TextAnalysisTerm],
        preview: String
    ) {
        self.generatedAt = generatedAt
        self.characterCount = characterCount
        self.nonWhitespaceCharacterCount = nonWhitespaceCharacterCount
        self.lineCount = lineCount
        self.paragraphCount = paragraphCount
        self.wordCount = wordCount
        self.uniqueWordCount = uniqueWordCount
        self.sentenceCount = sentenceCount
        self.topTerms = topTerms
        self.preview = preview
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case characterCount = "character_count"
        case nonWhitespaceCharacterCount = "non_whitespace_character_count"
        case lineCount = "line_count"
        case paragraphCount = "paragraph_count"
        case wordCount = "word_count"
        case uniqueWordCount = "unique_word_count"
        case sentenceCount = "sentence_count"
        case topTerms = "top_terms"
        case preview
    }
}

public enum MuniAnalyseRunner {
    private static let stopWords: Set<String> = [
        "a", "an", "and", "au", "aux", "avec", "ce", "ces", "cette", "dans", "de", "des",
        "du", "en", "est", "et", "for", "il", "is", "la", "le", "les", "mais", "ou", "par",
        "pour", "sur", "the", "to", "un", "une"
    ]

    public static func analyze(text: String, generatedAt: String? = nil) -> TextAnalysisReport {
        let timestamp = generatedAt ?? isoTimestamp()
        let normalizedNewlines = normalizeNewlines(in: text)
        let tokens = tokenize(text: text)
        let informativeTokens = tokens.filter { token in
            !isNumericToken(token) && !stopWords.contains(token)
        }

        var frequencies: [String: Int] = [:]
        for token in informativeTokens {
            frequencies[token, default: 0] += 1
        }

        let topTerms = frequencies
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(10)
            .map { TextAnalysisTerm(term: $0.key, occurrences: $0.value) }

        return TextAnalysisReport(
            generatedAt: timestamp,
            characterCount: text.count,
            nonWhitespaceCharacterCount: text.reduce(into: 0) { count, character in
                if !character.isWhitespace {
                    count += 1
                }
            },
            lineCount: lineCount(in: normalizedNewlines),
            paragraphCount: paragraphCount(in: normalizedNewlines),
            wordCount: tokens.count,
            uniqueWordCount: Set(tokens).count,
            sentenceCount: sentenceCount(in: text),
            topTerms: topTerms,
            preview: makePreview(from: text)
        )
    }

    private static func normalizeNewlines(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func lineCount(in text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private static func paragraphCount(in text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var paragraphCount = 0
        var inParagraph = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                inParagraph = false
                continue
            }

            if !inParagraph {
                paragraphCount += 1
                inParagraph = true
            }
        }

        return paragraphCount
    }

    private static func sentenceCount(in text: String) -> Int {
        text
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private static func tokenize(text: String) -> [String] {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func isNumericToken(_ token: String) -> Bool {
        !token.isEmpty && token.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func makePreview(from text: String) -> String {
        let condensed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(condensed.prefix(240))
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
