import Foundation
import MuniAnalyseInterop
import OrchivisteKitContracts
import OrchivisteKitInterop

@main
struct MuniAnalyseCLI {
    private static let version = "0.1.0"

    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())

            if args.isEmpty || args.first == "--help" {
                print(usage)
                return
            }

            if args.first == "--version" {
                print("MuniAnalyseCLI \(version)")
                return
            }

            guard args.first == "run" else {
                throw CLIError.invalidArguments("Expected 'run' command.")
            }

            guard let requestPath = value(after: "--request", in: args),
                  let resultPath = value(after: "--result", in: args) else {
                throw CLIError.invalidArguments("Missing --request or --result argument.")
            }

            let requestURL = URL(fileURLWithPath: requestPath)
            let resultURL = URL(fileURLWithPath: resultPath)
            let request = try ToolInteropService.loadRequest(from: requestURL)
            let result = CanonicalRunAdapter.execute(request: request)

            try ToolInteropService.writeResult(result, to: resultURL)
            printToolResult(result)

            if result.status == .failed {
                exit(1)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }

    private static func printToolResult(_ result: ToolResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        if let data = try? encoder.encode(result), let text = String(data: data, encoding: .utf8) {
            print(text)
            return
        }

        print("{\"status\":\"failed\",\"summary\":\"Unable to encode ToolResult.\"}")
    }

    private static let usage = """
Usage:
  muni-analyse-cli --help
  muni-analyse-cli --version
  muni-analyse-cli run --request /path/request.json --result /path/result.json

Notes:
  - V1 performs deterministic text-only analysis.
  - OCR is intentionally out of scope for this phase.
"""
}

enum CLIError: LocalizedError {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        }
    }
}
