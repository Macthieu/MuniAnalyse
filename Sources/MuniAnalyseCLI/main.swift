import Foundation
import MuniAnalyseCore

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

            let requestData = try Data(contentsOf: requestURL)
            let request = try JSONDecoder().decode(ToolRequest.self, from: requestData)
            let result = MuniAnalyseRunner.runPlaceholder(request: request)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let resultData = try encoder.encode(result)
            try resultData.write(to: resultURL, options: .atomic)
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

    private static let usage = """
Usage:
  muni-analyse-cli --help
  muni-analyse-cli --version
  muni-analyse-cli run --request /path/request.json --result /path/result.json
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
