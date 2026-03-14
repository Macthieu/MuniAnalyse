import Testing
@testable import MuniAnalyseCore

struct MuniAnalyseCoreTests {
    @Test
    func placeholderReturnsNotImplementedStatus() {
        let request = ToolRequest(requestID: "req-1", tool: "MuniAnalyse", action: "run")
        let result = MuniAnalyseRunner.runPlaceholder(request: request)

        #expect(result.status == ToolStatus.notImplemented)
        #expect(result.errors.first?.code == "NOT_IMPLEMENTED")
        #expect(result.requestID == "req-1")
    }
}
