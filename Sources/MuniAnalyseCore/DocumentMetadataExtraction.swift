import Foundation

public enum DocumentMetadataExtractionProvenance: String, Codable, Equatable, Sendable {
    case pdfText = "pdf_text"
    case filenameFallback = "filename_fallback"
}

public struct DocumentMetadataWarning: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let sourceFile: String?

    public init(code: String, message: String, sourceFile: String? = nil) {
        self.code = code
        self.message = message
        self.sourceFile = sourceFile
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case sourceFile = "source_file"
    }
}

public struct DocumentMetadataEntry: Codable, Equatable, Sendable {
    public let sourceFile: String
    public let documentType: String
    public let documentSubject: String
    public let documentDate: String
    public let extractionProvenance: String
    public let warnings: [DocumentMetadataWarning]

    public init(
        sourceFile: String,
        documentType: String,
        documentSubject: String,
        documentDate: String,
        extractionProvenance: String = DocumentMetadataExtractionProvenance.pdfText.rawValue,
        warnings: [DocumentMetadataWarning] = []
    ) {
        self.sourceFile = sourceFile
        self.documentType = documentType
        self.documentSubject = documentSubject
        self.documentDate = documentDate
        self.extractionProvenance = extractionProvenance
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceFile = try container.decode(String.self, forKey: .sourceFile)
        documentType = try container.decode(String.self, forKey: .documentType)
        documentSubject = try container.decode(String.self, forKey: .documentSubject)
        documentDate = try container.decode(String.self, forKey: .documentDate)
        extractionProvenance = try container.decodeIfPresent(String.self, forKey: .extractionProvenance)
            ?? DocumentMetadataExtractionProvenance.pdfText.rawValue
        warnings = try container.decodeIfPresent([DocumentMetadataWarning].self, forKey: .warnings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceFile, forKey: .sourceFile)
        try container.encode(documentType, forKey: .documentType)
        try container.encode(documentSubject, forKey: .documentSubject)
        try container.encode(documentDate, forKey: .documentDate)
        try container.encode(extractionProvenance, forKey: .extractionProvenance)
        try container.encode(warnings, forKey: .warnings)
    }

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case documentType = "document_type"
        case documentSubject = "document_subject"
        case documentDate = "document_date"
        case extractionProvenance = "extraction_provenance"
        case warnings
    }
}

public struct DocumentMetadataPayload: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let documents: [DocumentMetadataEntry]
    public let warnings: [DocumentMetadataWarning]

    public init(
        generatedAt: String,
        documents: [DocumentMetadataEntry],
        warnings: [DocumentMetadataWarning] = []
    ) {
        self.generatedAt = generatedAt
        self.documents = documents
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        documents = try container.decode([DocumentMetadataEntry].self, forKey: .documents)
        warnings = try container.decodeIfPresent([DocumentMetadataWarning].self, forKey: .warnings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(documents, forKey: .documents)
        try container.encode(warnings, forKey: .warnings)
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case documents
        case warnings
    }
}

public struct DocumentMetadataExtractionOutcome: Equatable, Sendable {
    public let entry: DocumentMetadataEntry

    public init(entry: DocumentMetadataEntry) {
        self.entry = entry
    }
}

public enum MuniAnalyseDocumentMetadataExtractor {
    public static func extractEntry(from text: String, sourceFile: String) -> DocumentMetadataEntry? {
        extractEntryWithDiagnostics(from: text, sourceFile: sourceFile)?.entry
    }

    public static func extractEntryWithDiagnostics(
        from text: String,
        sourceFile: String
    ) -> DocumentMetadataExtractionOutcome? {
        let normalizedSourceFile = normalizedSourceFileName(from: sourceFile)

        if let resolutionEntry = extractResolutionEntry(from: text, sourceFile: normalizedSourceFile) {
            return DocumentMetadataExtractionOutcome(entry: resolutionEntry)
        }

        if let agendaEntry = extractAgendaEntry(from: text, sourceFile: normalizedSourceFile) {
            return DocumentMetadataExtractionOutcome(entry: agendaEntry)
        }

        if let fallback = extractEntryFromSourceFileName(sourceFile: normalizedSourceFile) {
            return DocumentMetadataExtractionOutcome(entry: fallback)
        }

        return nil
    }

    private static func extractResolutionEntry(from text: String, sourceFile: String) -> DocumentMetadataEntry? {
        let foldedText = folded(text)
        guard foldedText.contains("resolution") else {
            return nil
        }

        guard let number = extractResolutionNumber(from: text),
              let subject = extractResolutionSubject(from: text),
              let date = extractNormalizedDate(from: text) else {
            return nil
        }

        return DocumentMetadataEntry(
            sourceFile: sourceFile,
            documentType: "Résolution NO \(number)",
            documentSubject: subject,
            documentDate: date,
            extractionProvenance: DocumentMetadataExtractionProvenance.pdfText.rawValue
        )
    }

    private static func extractAgendaEntry(from text: String, sourceFile: String) -> DocumentMetadataEntry? {
        let foldedText = folded(text)
        guard foldedText.contains("ordre du jour") else {
            return nil
        }

        guard let date = extractNormalizedDate(from: text) else {
            return nil
        }

        let subject = extractAgendaSubject(from: text) ?? "Séance du conseil"

        return DocumentMetadataEntry(
            sourceFile: sourceFile,
            documentType: "Ordre du jour",
            documentSubject: subject,
            documentDate: date,
            extractionProvenance: DocumentMetadataExtractionProvenance.pdfText.rawValue
        )
    }

    private static func extractResolutionNumber(from text: String) -> String? {
        let patterns = [
            #"(?im)\br[ée]solution\s*(?:no|n°|nº|numero|numéro|#)?\s*([0-9]{4}[\-/][0-9]{1,4})\b"#,
            #"\b([0-9]{4}[\-/][0-9]{1,4})\b"#
        ]

        for pattern in patterns {
            if let match = firstCapturedMatch(pattern: pattern, in: text) {
                return match
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: " ", with: "")
            }
        }

        return nil
    }

    private static func extractResolutionSubject(from text: String) -> String? {
        let lines = normalizedLines(from: text)

        if let subjectUnderHeading = extractResolutionTitleUnderHeading(from: lines) {
            return subjectUnderHeading
        }

        for line in lines {
            let foldedLine = folded(line)
            if foldedLine.hasPrefix("objet") || foldedLine.hasPrefix("titre") {
                if let subject = splitValueLine(line), !subject.isEmpty {
                    let cleaned = normalizeResolutionSubjectForNaming(subject)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                    return subject
                }
            }
        }

        for line in lines {
            let foldedLine = folded(line)
            guard foldedLine.contains("resolution") else {
                continue
            }
            if let subject = splitAfterDash(in: line), !subject.isEmpty, !isNoiseLine(subject) {
                let cleaned = normalizeResolutionSubjectForNaming(subject)
                if !cleaned.isEmpty {
                    return cleaned
                }
                return subject
            }
        }

        for line in lines where !isNoiseLine(line) {
            let cleaned = normalizeResolutionSubjectForNaming(line)
            if !cleaned.isEmpty {
                return cleaned
            }
            return line
        }

        return nil
    }

    private static func extractAgendaSubject(from text: String) -> String? {
        let lines = normalizedLines(from: text)

        if lines.contains(where: { folded($0).contains("seance du conseil") }) {
            return "Séance du conseil"
        }

        if let index = lines.firstIndex(where: { folded($0).contains("ordre du jour") }) {
            for line in lines.dropFirst(index + 1) where !isNoiseLine(line) {
                return line
            }
        }

        return nil
    }

    private static func extractNormalizedDate(from text: String) -> String? {
        if let iso = firstCapturedGroups(pattern: #"\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b"#, in: text, count: 3) {
            return normalizedDate(year: iso[0], month: iso[1], day: iso[2])
        }

        if let dmy = firstCapturedGroups(pattern: #"\b([0-3]?\d)[/-](\d{1,2})[/-](20\d{2})\b"#, in: text, count: 3) {
            return normalizedDate(year: dmy[2], month: dmy[1], day: dmy[0])
        }

        if let words = firstCapturedGroups(
            pattern: #"(?i)\b([0-3]?\d)\s*(janvier|janv|février|fevrier|févr|fevr|mars|avril|avr|mai|juin|juillet|juil|août|aout|septembre|sept|octobre|oct|novembre|nov|décembre|decembre|déc|dec)\.?\s*(20\d{2})\b"#,
            in: text,
            count: 3
        ) {
            let day = words[0]
            let monthName = folded(words[1]).replacingOccurrences(of: ".", with: "")
            let year = words[2]
            if let month = monthNumber(from: monthName) {
                return normalizedDate(year: year, month: String(month), day: day)
            }
        }

        return nil
    }

    private static func monthNumber(from month: String) -> Int? {
        switch month {
        case "janvier", "janv": return 1
        case "fevrier", "fevr", "fevr.", "fevrier.": return 2
        case "mars": return 3
        case "avril", "avr": return 4
        case "mai": return 5
        case "juin": return 6
        case "juillet", "juil": return 7
        case "aout": return 8
        case "septembre", "sept": return 9
        case "octobre", "oct": return 10
        case "novembre", "nov": return 11
        case "decembre", "dec": return 12
        default:
            return nil
        }
    }

    private static func normalizedDate(year: String, month: String, day: String) -> String? {
        guard let yearValue = Int(year),
              let monthValue = Int(month),
              let dayValue = Int(day),
              (1...12).contains(monthValue),
              (1...31).contains(dayValue),
              (2000...2100).contains(yearValue) else {
            return nil
        }

        return String(format: "%04d-%02d-%02d", yearValue, monthValue, dayValue)
    }

    private static func splitValueLine(_ line: String) -> String? {
        let separators = [":", "-", "–", "—"]
        for separator in separators {
            if let range = line.range(of: separator) {
                let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private static func splitAfterDash(in line: String) -> String? {
        let separators = [" – ", " — ", " - "]
        for separator in separators {
            if let range = line.range(of: separator) {
                let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private static func extractResolutionTitleUnderHeading(from lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            guard isResolutionHeadingLine(line) else {
                continue
            }

            let upperBound = min(lines.count, index + 6)
            if upperBound <= index + 1 {
                continue
            }

            for candidate in lines[(index + 1)..<upperBound] {
                if isSeparatorLine(candidate) || isNoiseLine(candidate) {
                    continue
                }

                guard isLikelyUppercaseTitleLine(candidate) else {
                    continue
                }

                let normalized = normalizeResolutionSubjectForNaming(candidate)
                if !normalized.isEmpty {
                    return normalized
                }
            }
        }

        return nil
    }

    private static func extractEntryFromSourceFileName(sourceFile: String) -> DocumentMetadataEntry? {
        let fileName = URL(fileURLWithPath: sourceFile).deletingPathExtension().lastPathComponent
        let components = splitFilenameComponents(fileName)
        guard components.count >= 2 else {
            return nil
        }

        let firstComponent = components[0]
        let foldedFirst = folded(firstComponent)
        let dateComponent = components.last ?? ""
        guard let date = extractNormalizedDate(from: dateComponent) else {
            return nil
        }

        let subjectComponents = components.dropFirst().dropLast()
        let subjectRaw = subjectComponents.joined(separator: " – ").trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = subjectRaw.isEmpty ? nil : subjectRaw

        if foldedFirst.contains("resolution"), let number = extractResolutionNumber(from: firstComponent) {
            return DocumentMetadataEntry(
                sourceFile: sourceFile,
                documentType: "Résolution NO \(number)",
                documentSubject: normalizeResolutionSubjectForNaming(subject ?? "Sans objet"),
                documentDate: date,
                extractionProvenance: DocumentMetadataExtractionProvenance.filenameFallback.rawValue,
                warnings: [filenameFallbackWarning(sourceFile: sourceFile)]
            )
        }

        if foldedFirst.contains("ordre du jour") {
            return DocumentMetadataEntry(
                sourceFile: sourceFile,
                documentType: "Ordre du jour",
                documentSubject: subject ?? "Séance du conseil",
                documentDate: date,
                extractionProvenance: DocumentMetadataExtractionProvenance.filenameFallback.rawValue,
                warnings: [filenameFallbackWarning(sourceFile: sourceFile)]
            )
        }

        return nil
    }

    private static func splitFilenameComponents(_ fileName: String) -> [String] {
        let separators = [" – ", " — ", " - "]

        for separator in separators where fileName.contains(separator) {
            return fileName
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return []
    }

    private static func filenameFallbackWarning(sourceFile: String) -> DocumentMetadataWarning {
        DocumentMetadataWarning(
            code: "METADATA_FROM_FILENAME_FALLBACK",
            message: "Metadata extracted from filename fallback because text extraction was not sufficient.",
            sourceFile: sourceFile
        )
    }

    private static func normalizeResolutionSubjectForNaming(_ subject: String) -> String {
        var value = subject
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let truncationPatterns = [
            #"(?i)\b(adopt[ée]e?|adopte)\s+le\b.*$"#,
            #"(?i)\b(?:en\s+date\s+du|date)\b.*$"#
        ]

        for pattern in truncationPatterns {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        value = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "'", with: "’")

        guard !value.isEmpty else {
            return value
        }

        if isLikelyUppercaseTitleLine(subject) {
            let original = value
            var normalized = value.lowercased(with: Locale(identifier: "fr_CA"))
            normalized = capitalizedFirstLetter(normalized)
            normalized = preserveAcronyms(from: original, in: normalized)
            normalized = normalized.replacingOccurrences(
                of: #"(?i)\binc\.?\b"#,
                with: "inc.",
                options: .regularExpression
            )
            normalized = normalized.replacingOccurrences(
                of: #"(?i)\binc\.+(?=\s|$)"#,
                with: "inc.",
                options: .regularExpression
            )
            normalized = capitalizeFirstWord(after: "pour", in: normalized)
            return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    private static func normalizedLines(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isNoiseLine(_ line: String) -> Bool {
        let foldedLine = folded(line)

        if foldedLine.contains("resolution") || foldedLine.contains("ordre du jour") {
            return true
        }

        if foldedLine.contains("adopte") || foldedLine.contains("seance") {
            return true
        }

        if extractNormalizedDate(from: line) != nil {
            return true
        }

        if line.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.union(.punctuationCharacters).contains($0) }) {
            return true
        }

        return false
    }

    private static func isResolutionHeadingLine(_ line: String) -> Bool {
        let normalized = folded(line)
        return normalized.contains("resolution") && extractResolutionNumber(from: line) != nil
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        let allowed = CharacterSet(charactersIn: "_-=–—.")
        return trimmed.unicodeScalars.allSatisfy { scalar in
            allowed.contains(scalar)
        }
    }

    private static func isLikelyUppercaseTitleLine(_ line: String) -> Bool {
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 8 else {
            return false
        }

        let uppercaseCount = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        return Double(uppercaseCount) / Double(letters.count) >= 0.75
    }

    private static func capitalizedFirstLetter(_ value: String) -> String {
        guard let first = value.first else {
            return value
        }
        let start = String(first).uppercased(with: Locale(identifier: "fr_CA"))
        return start + value.dropFirst()
    }

    private static func preserveAcronyms(from original: String, in normalized: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:[A-Z]\.){2,}"#) else {
            return normalized
        }

        let range = NSRange(original.startIndex..<original.endIndex, in: original)
        let matches = regex.matches(in: original, options: [], range: range)
        var result = normalized

        for match in matches {
            guard let tokenRange = Range(match.range, in: original) else {
                continue
            }
            let token = String(original[tokenRange])
            result = result.replacingOccurrences(of: token.lowercased(), with: token, options: [.caseInsensitive])
        }

        return result
    }

    private static func capitalizeFirstWord(after keyword: String, in value: String) -> String {
        let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword)
        let pattern = #"(?i)\b\#(escapedKeyword)\s+([\p{L}][\p{L}’'\-]*)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              let wordRange = Range(match.range(at: 1), in: value) else {
            return value
        }

        var mutable = value
        let word = String(mutable[wordRange])
        mutable.replaceSubrange(wordRange, with: capitalizedFirstLetter(word))
        return mutable
    }

    private static func normalizedSourceFileName(from sourceFile: String) -> String {
        let trimmed = sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastComponent = URL(fileURLWithPath: trimmed).lastPathComponent
        return lastComponent.isEmpty ? trimmed : lastComponent
    }

    private static func folded(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CA"))
            .lowercased()
    }

    private static func firstCapturedMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[capturedRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapturedGroups(pattern: String, in text: String, count: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > count else {
            return nil
        }

        var values: [String] = []
        values.reserveCapacity(count)

        for index in 1...count {
            guard let captured = Range(match.range(at: index), in: text) else {
                return nil
            }
            values.append(String(text[captured]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return values
    }
}
