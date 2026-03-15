import Foundation
import MuniAnalyseCore
import OrchivisteKitContracts

public enum CanonicalRunAdapterError: Error, Sendable {
    case unsupportedAction(String)
    case missingInput
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

private struct CanonicalExecutionContext: Sendable {
    let text: String
    let sourceKind: String
    let reportPath: String?
}

public enum CanonicalRunAdapter {
    public static func execute(request: ToolRequest) -> ToolResult {
        let startedAt = isoTimestamp()

        do {
            let context = try parseContext(from: request)
            let report = MuniAnalyseRunner.analyze(text: context.text, generatedAt: isoTimestamp())
            let warningMessages = warnings(for: report)
            let finalStatus: ToolStatus = warningMessages.isEmpty ? .succeeded : .needsReview
            let finishedAt = isoTimestamp()

            var outputArtifacts: [ArtifactDescriptor] = []
            if let reportPath = context.reportPath {
                try writeReport(report, toPath: reportPath)
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
                outputArtifacts: outputArtifacts,
                errors: [],
                metadata: metadata(from: report, sourceKind: context.sourceKind, warnings: warningMessages)
            )
        } catch let adapterError as CanonicalRunAdapterError {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [adapterError.toolError],
                summary: "Canonical text analysis request failed."
            )
        } catch {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [CanonicalRunAdapterError.runtimeFailure(error.localizedDescription).toolError],
                summary: "Canonical text analysis request failed with an unexpected runtime error."
            )
        }
    }

    private static func parseContext(from request: ToolRequest) throws -> CanonicalExecutionContext {
        try validateAction(request.action)

        let inlineText = try optionalStringParameter("text", in: request)
        let sourcePath = try optionalStringParameter("source_path", in: request)
        let reportPath = try optionalStringParameter("report_path", in: request)

        if let inlineText, !inlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CanonicalExecutionContext(text: inlineText, sourceKind: "inline_text", reportPath: reportPath)
        }

        if let sourcePath {
            let text = try readText(fromPath: sourcePath)
            return CanonicalExecutionContext(text: text, sourceKind: "source_path", reportPath: reportPath)
        }

        if let inputArtifact = request.inputArtifacts.first(where: { $0.kind == .input }) {
            let path = resolvePathFromURIOrPath(inputArtifact.uri)
            let text = try readText(fromPath: path)
            return CanonicalExecutionContext(text: text, sourceKind: "input_artifact", reportPath: reportPath)
        }

        if let inlineText {
            return CanonicalExecutionContext(text: inlineText, sourceKind: "inline_text", reportPath: reportPath)
        }

        throw CanonicalRunAdapterError.missingInput
    }

    private static func validateAction(_ rawAction: String) throws {
        let normalized = rawAction
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "run", "analyze":
            return
        default:
            throw CanonicalRunAdapterError.unsupportedAction(rawAction)
        }
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

    private static func resolvePathLikeValue(forKey key: String, value: String) -> String {
        switch key {
        case "source_path", "report_path":
            return resolvePathFromURIOrPath(value)
        default:
            return value
        }
    }

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

    private static func writeReport(_ report: TextAnalysisReport, toPath path: String) throws {
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            try data.write(to: url, options: .atomic)
        } catch {
            throw CanonicalRunAdapterError.reportWriteFailed(
                "Unable to write analysis report at \(path): \(error.localizedDescription)"
            )
        }
    }

    private static func warnings(for report: TextAnalysisReport) -> [String] {
        var warnings: [String] = []

        if report.wordCount == 0 {
            warnings.append("Input text is empty after normalization.")
        }

        if report.characterCount > 0 && report.wordCount < 3 {
            warnings.append("Input text is very short; review analysis reliability.")
        }

        return warnings
    }

    private static func metadata(
        from report: TextAnalysisReport,
        sourceKind: String,
        warnings: [String]
    ) -> [String: JSONValue] {
        var metadata: [String: JSONValue] = [
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

    private static func makeResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        status: ToolStatus,
        summary: String,
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
                    stage: "analyse_text",
                    percent: 75,
                    message: "Deterministic text analysis executed.",
                    occurredAt: finishedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: status,
                    stage: "analysis_complete",
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
                    stage: "analysis_failed",
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
