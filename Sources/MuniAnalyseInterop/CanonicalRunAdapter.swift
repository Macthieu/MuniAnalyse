import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
import MuniAnalyseCore
import OrchivisteKitContracts

public enum CanonicalRunAdapterError: Error, Sendable {
    case unsupportedAction(String)
    case missingInput
    case missingExtractionOutputPath
    case missingExtractionSources
    case invalidParameter(String, String)
    case sourceReadFailed(String)
    case reportWriteFailed(String)
    case runtimeFailure(String)

    var toolError: ToolError {
        switch self {
        case .unsupportedAction(let action):
            return ToolError(
                code: "UNSUPPORTED_ACTION",
                message: "Unsupported action: \(action)",
                retryable: false
            )
        case .missingInput:
            return ToolError(
                code: "MISSING_INPUT",
                message: "Provide input text via parameters.text, parameters.source_path, or an input artifact.",
                retryable: false
            )
        case .missingExtractionOutputPath:
            return ToolError(
                code: "MISSING_OUTPUT_PATH",
                message: "Provide parameters.document_metadata_output_path when extract_document_metadata=true.",
                retryable: false
            )
        case .missingExtractionSources:
            return ToolError(
                code: "MISSING_EXTRACTION_SOURCES",
                message: "Provide PDF sources via parameters.source_paths, parameters.source_path, or input artifacts.",
                retryable: false
            )
        case .invalidParameter(let parameter, let reason):
            return ToolError(
                code: "INVALID_PARAMETER",
                message: "Invalid parameter \(parameter): \(reason)",
                retryable: false
            )
        case .sourceReadFailed(let reason):
            return ToolError(
                code: "SOURCE_READ_FAILED",
                message: reason,
                retryable: false
            )
        case .reportWriteFailed(let reason):
            return ToolError(
                code: "REPORT_WRITE_FAILED",
                message: reason,
                retryable: true
            )
        case .runtimeFailure(let reason):
            return ToolError(
                code: "RUNTIME_FAILURE",
                message: reason,
                retryable: false
            )
        }
    }
}

private struct TextAnalysisExecutionContext: Sendable {
    let text: String
    let sourceKind: String
    let reportPath: String?
}

private struct MetadataExtractionExecutionContext: Sendable {
    let sourcePaths: [String]
    let outputPath: String
}

public enum CanonicalRunAdapter {
    public static func execute(request: ToolRequest) -> ToolResult {
        let startedAt = isoTimestamp()

        do {
            try validateAction(request.action)

            if let extractionContext = try parseMetadataExtractionContext(from: request) {
                return try executeMetadataExtraction(
                    request: request,
                    context: extractionContext,
                    startedAt: startedAt
                )
            }

            let context = try parseTextAnalysisContext(from: request)
            return try executeTextAnalysis(request: request, context: context, startedAt: startedAt)
        } catch let adapterError as CanonicalRunAdapterError {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [adapterError.toolError],
                summary: "Canonical MuniAnalyse request failed."
            )
        } catch {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [CanonicalRunAdapterError.runtimeFailure(error.localizedDescription).toolError],
                summary: "Canonical MuniAnalyse request failed with an unexpected runtime error."
            )
        }
    }

    private static func executeTextAnalysis(
        request: ToolRequest,
        context: TextAnalysisExecutionContext,
        startedAt: String
    ) throws -> ToolResult {
        let report = MuniAnalyseRunner.analyze(text: context.text, generatedAt: isoTimestamp())
        let warningMessages = analysisWarnings(for: report)
        let finalStatus: ToolStatus = warningMessages.isEmpty ? .succeeded : .needsReview
        let finishedAt = isoTimestamp()

        var outputArtifacts: [ArtifactDescriptor] = []
        if let reportPath = context.reportPath {
            try writeJSONFile(report, toPath: reportPath, failurePrefix: "analysis report")
            outputArtifacts.append(
                ArtifactDescriptor(
                    id: "analysis_report",
                    kind: .report,
                    uri: fileURI(forPath: reportPath),
                    mediaType: "application/json",
                    metadata: [
                        "word_count": .number(Double(report.wordCount)),
                        "sentence_count": .number(Double(report.sentenceCount))
                    ]
                )
            )
        }

        let summary: String
        if warningMessages.isEmpty {
            summary = "Text analysis completed successfully."
        } else {
            summary = "Text analysis completed with review warnings."
        }

        return makeResult(
            request: request,
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: finalStatus,
            summary: summary,
            processingStage: "analyse_text",
            processingMessage: "Deterministic text analysis executed.",
            completionStage: "analysis_complete",
            outputArtifacts: outputArtifacts,
            errors: [],
            metadata: analysisMetadata(from: report, sourceKind: context.sourceKind, warnings: warningMessages)
        )
    }

    private static func executeMetadataExtraction(
        request: ToolRequest,
        context: MetadataExtractionExecutionContext,
        startedAt: String
    ) throws -> ToolResult {
        var extractedDocuments: [DocumentMetadataEntry] = []
        var warningMessages: [String] = []

        for sourcePath in context.sourcePaths {
            do {
                let text = try readSourceTextForExtraction(fromPath: sourcePath)
                if let document = MuniAnalyseDocumentMetadataExtractor.extractEntry(from: text, sourceFile: sourcePath) {
                    extractedDocuments.append(document)
                } else {
                    warningMessages.append("No supported metadata extracted for \(URL(fileURLWithPath: sourcePath).lastPathComponent).")
                }
            } catch {
                warningMessages.append("Unable to read \(sourcePath): \(error.localizedDescription)")
            }
        }

        guard !extractedDocuments.isEmpty else {
            throw CanonicalRunAdapterError.runtimeFailure(
                "Unable to extract document metadata from provided sources."
            )
        }

        let payload = DocumentMetadataPayload(generatedAt: isoTimestamp(), documents: extractedDocuments)
        try writeJSONFile(payload, toPath: context.outputPath, failurePrefix: "document metadata")

        let finalStatus: ToolStatus = warningMessages.isEmpty ? .succeeded : .needsReview
        let finishedAt = isoTimestamp()

        let outputArtifacts: [ArtifactDescriptor] = [
            ArtifactDescriptor(
                id: "document_metadata",
                kind: .metadata,
                uri: fileURI(forPath: context.outputPath),
                mediaType: "application/json",
                metadata: [
                    "documents_extracted": .number(Double(extractedDocuments.count))
                ]
            )
        ]

        let summary: String
        if warningMessages.isEmpty {
            summary = "Document metadata extraction completed successfully."
        } else {
            summary = "Document metadata extraction completed with review warnings."
        }

        return makeResult(
            request: request,
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: finalStatus,
            summary: summary,
            processingStage: "extract_document_metadata",
            processingMessage: "Deterministic document metadata extraction executed.",
            completionStage: "extraction_complete",
            outputArtifacts: outputArtifacts,
            errors: [],
            metadata: extractionMetadata(
                sourcePaths: context.sourcePaths,
                outputPath: context.outputPath,
                documents: extractedDocuments,
                warnings: warningMessages
            )
        )
    }

    private static func parseTextAnalysisContext(from request: ToolRequest) throws -> TextAnalysisExecutionContext {
        let inlineText = try optionalStringParameter("text", in: request)
        let sourcePath = try optionalStringParameter("source_path", in: request)
        let reportPath = try optionalStringParameter("report_path", in: request)

        if let inlineText, !inlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TextAnalysisExecutionContext(text: inlineText, sourceKind: "inline_text", reportPath: reportPath)
        }

        if let sourcePath {
            let text = try readText(fromPath: sourcePath)
            return TextAnalysisExecutionContext(text: text, sourceKind: "source_path", reportPath: reportPath)
        }

        if let inputArtifact = request.inputArtifacts.first(where: { $0.kind == .input }) {
            let path = resolvePathFromURIOrPath(inputArtifact.uri)
            let text = try readText(fromPath: path)
            return TextAnalysisExecutionContext(text: text, sourceKind: "input_artifact", reportPath: reportPath)
        }

        if let inlineText {
            return TextAnalysisExecutionContext(text: inlineText, sourceKind: "inline_text", reportPath: reportPath)
        }

        throw CanonicalRunAdapterError.missingInput
    }

    private static func parseMetadataExtractionContext(from request: ToolRequest) throws -> MetadataExtractionExecutionContext? {
        let action = normalizeAction(request.action)
        let extractionFlag = try optionalBoolParameter("extract_document_metadata", in: request) ?? false

        let explicitOutputPath = try optionalStringParameter("document_metadata_output_path", in: request)
        let rawOutputPath = optionalStringFromRawValue(request.parameters["document_metadata_output_path"])
        let legacyOutputPath = try optionalStringParameter("document_metadata_path", in: request)
        let outputPath = explicitOutputPath ?? rawOutputPath ?? legacyOutputPath

        let extractionRequested = extractionFlag || outputPath != nil || action == "extract" || action == "extract-metadata"
        guard extractionRequested else {
            return nil
        }

        guard let outputPath, !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanonicalRunAdapterError.missingExtractionOutputPath
        }

        let sourcePaths = try resolveExtractionSourcePaths(from: request)
        guard !sourcePaths.isEmpty else {
            throw CanonicalRunAdapterError.missingExtractionSources
        }

        return MetadataExtractionExecutionContext(sourcePaths: sourcePaths, outputPath: outputPath)
    }

    private static func resolveExtractionSourcePaths(from request: ToolRequest) throws -> [String] {
        var rawCandidates: [String] = []

        if let sourcePathsValue = request.parameters["source_paths"] {
            switch sourcePathsValue {
            case .array(let values):
                for value in values {
                    switch value {
                    case .string(let raw):
                        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            rawCandidates.append(resolvePathFromURIOrPath(trimmed))
                        }
                    default:
                        throw CanonicalRunAdapterError.invalidParameter(
                            "source_paths",
                            "expected an array of strings"
                        )
                    }
                }
            default:
                throw CanonicalRunAdapterError.invalidParameter("source_paths", "expected array")
            }
        }

        if let sourcePath = try optionalStringParameter("source_path", in: request),
           !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawCandidates.append(sourcePath)
        }

        let inputArtifacts = request.inputArtifacts.filter { $0.kind == .input }
        for artifact in inputArtifacts {
            let resolved = resolvePathFromURIOrPath(artifact.uri)
            let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                rawCandidates.append(trimmed)
            }
        }

        var expandedPaths: [String] = []
        for candidate in rawCandidates {
            expandedPaths.append(contentsOf: expandSourceCandidatePath(candidate))
        }

        var seen = Set<String>()
        var uniquePaths: [String] = []
        for path in expandedPaths {
            if seen.insert(path).inserted {
                uniquePaths.append(path)
            }
        }

        return uniquePaths
    }

    private static func expandSourceCandidatePath(_ path: String) -> [String] {
        let url = URL(fileURLWithPath: path)

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else {
            return [path]
        }

        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [path]
        }

        let regularFiles = files.filter { candidate in
            (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }

        let pdfFiles = regularFiles.filter { $0.pathExtension.lowercased() == "pdf" }
        let selected = pdfFiles.isEmpty ? regularFiles : pdfFiles
        let ordered = selected.map(\.path).sorted()

        return ordered.isEmpty ? [path] : ordered
    }

    private static func validateAction(_ rawAction: String) throws {
        switch normalizeAction(rawAction) {
        case "run", "analyze", "extract", "extract-metadata":
            return
        default:
            throw CanonicalRunAdapterError.unsupportedAction(rawAction)
        }
    }

    private static func normalizeAction(_ rawAction: String) -> String {
        rawAction
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func optionalStringParameter(_ key: String, in request: ToolRequest) throws -> String? {
        guard let value = request.parameters[key] else {
            return nil
        }

        switch value {
        case .string(let rawValue):
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ""
            }
            return resolvePathLikeValue(forKey: key, value: trimmed)
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected string")
        }
    }

    private static func optionalStringFromRawValue(_ value: JSONValue?) -> String? {
        guard case .string(let rawValue) = value else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalBoolParameter(_ key: String, in request: ToolRequest) throws -> Bool? {
        guard let value = request.parameters[key] else {
            return nil
        }

        switch value {
        case .bool(let rawValue):
            return rawValue
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected bool")
        }
    }

    private static func resolvePathLikeValue(forKey key: String, value: String) -> String {
        switch key {
        case "source_path", "report_path", "document_metadata_output_path", "document_metadata_path":
            return resolvePathFromURIOrPath(value)
        default:
            return value
        }
    }

    private static func readSourceTextForExtraction(fromPath path: String) throws -> String {
#if canImport(PDFKit)
        if path.lowercased().hasSuffix(".pdf"), let pdfText = readPDFText(fromPath: path) {
            return pdfText
        }
#endif
        return try readText(fromPath: path)
    }

#if canImport(PDFKit)
    private static func readPDFText(fromPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let document = PDFDocument(url: url) else {
            return nil
        }

        guard let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        return text
    }
#endif

    private static func readText(fromPath path: String) throws -> String {
        let fileURL = URL(fileURLWithPath: path)

        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            do {
                let data = try Data(contentsOf: fileURL)
                return String(decoding: data, as: UTF8.self)
            } catch {
                throw CanonicalRunAdapterError.sourceReadFailed(
                    "Unable to read source text at \(path): \(error.localizedDescription)"
                )
            }
        }
    }

    private static func writeJSONFile<T: Encodable>(
        _ value: T,
        toPath path: String,
        failurePrefix: String
    ) throws {
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            throw CanonicalRunAdapterError.reportWriteFailed(
                "Unable to write \(failurePrefix) at \(path): \(error.localizedDescription)"
            )
        }
    }

    private static func analysisWarnings(for report: TextAnalysisReport) -> [String] {
        var warnings: [String] = []

        if report.wordCount == 0 {
            warnings.append("Input text is empty after normalization.")
        }

        if report.characterCount > 0 && report.wordCount < 3 {
            warnings.append("Input text is very short; review analysis reliability.")
        }

        return warnings
    }

    private static func analysisMetadata(
        from report: TextAnalysisReport,
        sourceKind: String,
        warnings: [String]
    ) -> [String: JSONValue] {
        var metadata: [String: JSONValue] = [
            "mode": .string("text_analysis"),
            "source_kind": .string(sourceKind),
            "character_count": .number(Double(report.characterCount)),
            "non_whitespace_character_count": .number(Double(report.nonWhitespaceCharacterCount)),
            "line_count": .number(Double(report.lineCount)),
            "paragraph_count": .number(Double(report.paragraphCount)),
            "word_count": .number(Double(report.wordCount)),
            "unique_word_count": .number(Double(report.uniqueWordCount)),
            "sentence_count": .number(Double(report.sentenceCount)),
            "preview": .string(report.preview),
            "top_terms": .array(
                report.topTerms.map {
                    .object([
                        "term": .string($0.term),
                        "occurrences": .number(Double($0.occurrences))
                    ])
                }
            )
        ]

        if !warnings.isEmpty {
            metadata["warnings"] = .array(warnings.map { .string($0) })
        }

        return metadata
    }

    private static func extractionMetadata(
        sourcePaths: [String],
        outputPath: String,
        documents: [DocumentMetadataEntry],
        warnings: [String]
    ) -> [String: JSONValue] {
        var metadata: [String: JSONValue] = [
            "mode": .string("extract_document_metadata"),
            "source_count": .number(Double(sourcePaths.count)),
            "documents_extracted": .number(Double(documents.count)),
            "document_metadata_output_path": .string(outputPath),
            "source_paths": .array(sourcePaths.map { .string($0) })
        ]

        if !warnings.isEmpty {
            metadata["warnings"] = .array(warnings.map { .string($0) })
        }

        return metadata
    }

    private static func makeResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        status: ToolStatus,
        summary: String,
        processingStage: String,
        processingMessage: String,
        completionStage: String,
        outputArtifacts: [ArtifactDescriptor],
        errors: [ToolError],
        metadata: [String: JSONValue]
    ) -> ToolResult {
        ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: status,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "load_input",
                    percent: 20,
                    message: "Canonical request parsed.",
                    occurredAt: startedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: processingStage,
                    percent: 75,
                    message: processingMessage,
                    occurredAt: finishedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: status,
                    stage: completionStage,
                    percent: 100,
                    message: summary,
                    occurredAt: finishedAt
                )
            ],
            outputArtifacts: outputArtifacts,
            errors: errors,
            summary: summary,
            metadata: metadata
        )
    }

    private static func makeFailureResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        errors: [ToolError],
        summary: String
    ) -> ToolResult {
        ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: .failed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "load_input",
                    percent: 20,
                    message: "Canonical request parsed.",
                    occurredAt: startedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: .failed,
                    stage: "request_failed",
                    percent: 100,
                    message: summary,
                    occurredAt: finishedAt
                )
            ],
            outputArtifacts: [],
            errors: errors,
            summary: summary,
            metadata: [
                "action": .string(request.action)
            ]
        )
    }

    private static func resolvePathFromURIOrPath(_ candidate: String) -> String {
        guard let url = URL(string: candidate), url.isFileURL else {
            return candidate
        }
        return url.path
    }

    private static func fileURI(forPath path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
