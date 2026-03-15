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
}
