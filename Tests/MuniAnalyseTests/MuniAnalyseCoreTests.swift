import Foundation
import OrchivisteKitContracts
import Testing
@testable import MuniAnalyseCore
@testable import MuniAnalyseInterop

struct MuniAnalyseCoreTests {
    @Test
    func analyzeComputesDeterministicMetrics() {
        let report = MuniAnalyseRunner.analyze(
            text: "Bonjour monde. Bonjour ville!",
            generatedAt: "2026-03-15T00:00:00Z"
        )

        #expect(report.wordCount == 4)
        #expect(report.uniqueWordCount == 3)
        #expect(report.sentenceCount == 2)
        #expect(report.lineCount == 1)
        #expect(report.topTerms.first?.term == "bonjour")
        #expect(report.topTerms.first?.occurrences == 2)
    }

    @Test
    func canonicalRunWithInlineTextSucceeds() {
        let request = ToolRequest(
            requestID: "req-inline",
            tool: "MuniAnalyse",
            action: "run",
            parameters: [
                "text": .string("Avis de seance municipale valide et public.")
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded)
        #expect(result.errors.isEmpty)
        #expect(result.progressEvents.last?.status == .succeeded)
    }

    @Test
    func canonicalRunWithEmptyTextReturnsNeedsReview() {
        let request = ToolRequest(
            requestID: "req-empty",
            tool: "MuniAnalyse",
            action: "run",
            parameters: [
                "text": .string("   ")
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .needsReview)
        #expect(result.errors.isEmpty)
        #expect(result.progressEvents.last?.status == .needsReview)
    }

    @Test
    func canonicalRunFailsWithoutInput() {
        let request = ToolRequest(
            requestID: "req-missing",
            tool: "MuniAnalyse",
            action: "run"
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .failed)
        #expect(result.errors.first?.code == "MISSING_INPUT")
    }

    @Test
    func canonicalRunWritesReportArtifactWhenRequested() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muni-analyse-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let reportPath = tempDirectory.appendingPathComponent("analysis-report.json").path

        let request = ToolRequest(
            requestID: "req-report",
            tool: "MuniAnalyse",
            action: "run",
            parameters: [
                "text": .string("Texte d'analyse pour produire un rapport JSON."),
                "report_path": .string(reportPath)
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded)
        #expect(result.outputArtifacts.count == 1)
        #expect(result.outputArtifacts.first?.kind == .report)
        #expect(FileManager.default.fileExists(atPath: reportPath))
    }

    @Test
    func canonicalRunExtractsDocumentMetadataFromPdfSources() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muni-analyse-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let resolutionPath = tempDirectory.appendingPathComponent("source-resolution.pdf").path
        let agendaPath = tempDirectory.appendingPathComponent("source-ordre.pdf").path
        let outputPath = tempDirectory.appendingPathComponent("document_metadata.json").path

        let resolutionText = """
RÉSOLUTION NO 2025-54
Objet : Extension du délai de construction pour Plantation d’arbres M.M. inc.
Adoptée le 3 février 2025
"""

        let agendaText = """
ORDRE DU JOUR
Séance du conseil
17 mars 2025
"""

        try resolutionText.write(to: URL(fileURLWithPath: resolutionPath), atomically: true, encoding: .utf8)
        try agendaText.write(to: URL(fileURLWithPath: agendaPath), atomically: true, encoding: .utf8)

        let request = ToolRequest(
            requestID: "req-extract",
            tool: "MuniAnalyse",
            action: "run",
            parameters: [
                "extract_document_metadata": .bool(true),
                "source_paths": .array([.string(resolutionPath), .string(agendaPath)]),
                "document_metadata_output_path": .string(outputPath)
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded)
        #expect(result.errors.isEmpty)
        #expect(result.outputArtifacts.first?.id == "document_metadata")
        #expect(result.outputArtifacts.first?.kind == .metadata)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let payload = try JSONDecoder().decode(DocumentMetadataTestPayload.self, from: data)

        #expect(payload.documents.count == 2)

        let resolutionEntry = payload.documents.first { $0.sourceFile == "source-resolution.pdf" }
        #expect(resolutionEntry?.documentType == "Résolution NO 2025-54")
        #expect(resolutionEntry?.documentSubject == "Extension du délai de construction pour Plantation d’arbres M.M. inc.")
        #expect(resolutionEntry?.documentDate == "2025-02-03")

        let agendaEntry = payload.documents.first { $0.sourceFile == "source-ordre.pdf" }
        #expect(agendaEntry?.documentType == "Ordre du jour")
        #expect(agendaEntry?.documentSubject == "Séance du conseil")
        #expect(agendaEntry?.documentDate == "2025-03-17")
    }
}

private struct DocumentMetadataTestPayload: Decodable {
    let documents: [DocumentMetadataTestEntry]
}

private struct DocumentMetadataTestEntry: Decodable {
    let sourceFile: String
    let documentType: String
    let documentSubject: String
    let documentDate: String

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case documentType = "document_type"
        case documentSubject = "document_subject"
        case documentDate = "document_date"
    }
}
