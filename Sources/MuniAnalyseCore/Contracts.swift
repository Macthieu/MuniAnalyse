import Foundation

public enum ToolStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case needsReview = "needs_review"
    case cancelled
    case notImplemented = "not_implemented"
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct ArtifactDescriptor: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var uri: String

    public init(id: String, kind: String, uri: String) {
        self.id = id
        self.kind = kind
        self.uri = uri
    }
}

public struct ToolRequest: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var requestID: String
    public var correlationID: String?
    public var tool: String
    public var action: String
    public var workspacePath: String?
    public var inputArtifacts: [ArtifactDescriptor]
    public var parameters: [String: JSONValue]

    public init(
        schemaVersion: String = "1.0",
        requestID: String,
        correlationID: String? = nil,
        tool: String,
        action: String,
        workspacePath: String? = nil,
        inputArtifacts: [ArtifactDescriptor] = [],
        parameters: [String: JSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.correlationID = correlationID
        self.tool = tool
        self.action = action
        self.workspacePath = workspacePath
        self.inputArtifacts = inputArtifacts
        self.parameters = parameters
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case correlationID = "correlation_id"
        case tool
        case action
        case workspacePath = "workspace_path"
        case inputArtifacts = "input_artifacts"
        case parameters
    }
}

public struct ToolError: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var retryable: Bool

    public init(code: String, message: String, retryable: Bool = false) {
        self.code = code
        self.message = message
        self.retryable = retryable
    }
}

public struct ProgressEvent: Codable, Equatable, Sendable {
    public var requestID: String
    public var status: ToolStatus
    public var stage: String
    public var percent: Int
    public var message: String
    public var occurredAt: String

    public init(
        requestID: String,
        status: ToolStatus,
        stage: String,
        percent: Int,
        message: String,
        occurredAt: String
    ) {
        self.requestID = requestID
        self.status = status
        self.stage = stage
        self.percent = percent
        self.message = message
        self.occurredAt = occurredAt
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case stage
        case percent
        case message
        case occurredAt = "occurred_at"
    }
}

public struct ToolResult: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var requestID: String
    public var tool: String
    public var status: ToolStatus
    public var startedAt: String
    public var finishedAt: String
    public var progressEvents: [ProgressEvent]
    public var outputArtifacts: [ArtifactDescriptor]
    public var errors: [ToolError]
    public var summary: String

    public init(
        schemaVersion: String = "1.0",
        requestID: String,
        tool: String,
        status: ToolStatus,
        startedAt: String,
        finishedAt: String,
        progressEvents: [ProgressEvent],
        outputArtifacts: [ArtifactDescriptor],
        errors: [ToolError],
        summary: String
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.tool = tool
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.progressEvents = progressEvents
        self.outputArtifacts = outputArtifacts
        self.errors = errors
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case tool
        case status
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case progressEvents = "progress_events"
        case outputArtifacts = "output_artifacts"
        case errors
        case summary
    }
}
