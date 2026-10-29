import CoreFoundation
import Foundation

/// Errors raised while producing canonical JSON bytes.
public enum CanonicalJSONError: Error, Hashable, Sendable {
    /// The value is not one of: `NSNull`, `Bool`, integer, `String`, `[Any]`, `[String: Any]`.
    case unsupportedValue
    /// Two keys of the same object are equal after Unicode NFC normalization.
    case duplicateNormalizedKey
    /// A key that the ``CanonicalJSONKeyPolicy`` forbids appears in an object.
    case forbiddenKey(String)
    /// A value under a logical-path key is not a relative, normalized path.
    case invalidLogicalPath
}

/// Per-key rules applied while canonicalizing objects.
///
/// The default policy (``none``) applies no key rules.
public struct CanonicalJSONKeyPolicy: Hashable, Sendable {
    /// Keys that must not appear anywhere in the value, e.g. volatile fields such as timestamps.
    public var forbiddenKeys: Set<String>
    /// Keys whose values are relative logical paths.
    public var logicalPathKeys: Set<String>
    /// Key suffixes whose values are relative logical paths (e.g. `"_path"`).
    public var logicalPathKeySuffixes: Set<String>

    public init(
        forbiddenKeys: Set<String> = [],
        logicalPathKeys: Set<String> = [],
        logicalPathKeySuffixes: Set<String> = []
    ) {
        self.forbiddenKeys = forbiddenKeys
        self.logicalPathKeys = logicalPathKeys
        self.logicalPathKeySuffixes = logicalPathKeySuffixes
    }

    public static let none = CanonicalJSONKeyPolicy()

    func isLogicalPathKey(_ key: String) -> Bool {
        logicalPathKeys.contains(key) || logicalPathKeySuffixes.contains { key.hasSuffix($0) }
    }
}

/// Encodes a restricted JSON value set as canonical bytes: NFC strings, object keys sorted by Unicode scalar
/// value, no insignificant whitespace, integers only (no floating point).
///
/// Values under logical-path keys must be relative paths; backslashes become `/`, and empty, `.` and `..`
/// segments are rejected.
public func canonicalJSONData(_ value: Any, keyPolicy: CanonicalJSONKeyPolicy = .none) throws -> Data {
    try normalizeCanonicalJSONValue(value, keyPolicy: keyPolicy).render()
}

/// Returns the lowercase hex SHA-256 of ``canonicalJSONData(_:keyPolicy:)``.
public func canonicalJSONSHA256(_ value: Any, keyPolicy: CanonicalJSONKeyPolicy = .none) throws -> String {
    try CanonicalSHA256.hexDigest(for: canonicalJSONData(value, keyPolicy: keyPolicy))
}

private enum CanonicalJSONNode {
    case null
    case boolean(Bool)
    case integer(Int)
    case string(String)
    case array([CanonicalJSONNode])
    case object([(String, CanonicalJSONNode)])

    func render() throws -> Data {
        switch self {
        case .null:
            return Data("null".utf8)
        case let .boolean(value):
            return Data((value ? "true" : "false").utf8)
        case let .integer(value):
            return Data(String(value).utf8)
        case let .string(value):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return try encoder.encode(value)
        case let .array(values):
            var data = Data("[".utf8)
            for (index, value) in values.enumerated() {
                if index > 0 {
                    data.append(contentsOf: ",".utf8)
                }
                try data.append(value.render())
            }
            data.append(contentsOf: "]".utf8)
            return data
        case let .object(entries):
            var data = Data("{".utf8)
            for (index, entry) in entries.enumerated() {
                if index > 0 {
                    data.append(contentsOf: ",".utf8)
                }
                try data.append(CanonicalJSONNode.string(entry.0).render())
                data.append(contentsOf: ":".utf8)
                try data.append(entry.1.render())
            }
            data.append(contentsOf: "}".utf8)
            return data
        }
    }
}

private func normalizeCanonicalJSONValue(_ value: Any, keyPolicy: CanonicalJSONKeyPolicy) throws -> CanonicalJSONNode {
    if value is NSNull {
        return .null
    }
    if type(of: value) == Bool.self, let boolean = value as? Bool {
        return .boolean(boolean)
    }
    if type(of: value) == Int.self, let integer = value as? Int {
        return .integer(integer)
    }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .boolean(number.boolValue)
        }
        let integerTypes: Set<String> = ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"]
        guard integerTypes.contains(String(cString: number.objCType)),
              let integer = Int(number.stringValue),
              String(integer) == number.stringValue
        else {
            throw CanonicalJSONError.unsupportedValue
        }
        return .integer(integer)
    }
    if let string = value as? String {
        return .string(string.precomposedStringWithCanonicalMapping)
    }
    if let dictionary = value as? [String: Any] {
        var normalized: [(String, CanonicalJSONNode)] = []
        for (key, child) in dictionary {
            let normalizedKey = key.precomposedStringWithCanonicalMapping
            guard !normalized.contains(where: { $0.0 == normalizedKey }) else {
                throw CanonicalJSONError.duplicateNormalizedKey
            }
            guard !keyPolicy.forbiddenKeys.contains(normalizedKey) else {
                throw CanonicalJSONError.forbiddenKey(normalizedKey)
            }
            if keyPolicy.isLogicalPathKey(normalizedKey) {
                guard let path = child as? String else {
                    throw CanonicalJSONError.invalidLogicalPath
                }
                try normalized.append((normalizedKey, .string(normalizeLogicalPath(path))))
            } else {
                try normalized.append((normalizedKey, normalizeCanonicalJSONValue(child, keyPolicy: keyPolicy)))
            }
        }
        normalized.sort { left, right in
            left.0.unicodeScalars.lexicographicallyPrecedes(right.0.unicodeScalars) {
                $0.value < $1.value
            }
        }
        return .object(normalized)
    }
    if let array = value as? [Any] {
        return try .array(array.map { try normalizeCanonicalJSONValue($0, keyPolicy: keyPolicy) })
    }
    throw CanonicalJSONError.unsupportedValue
}

private func normalizeLogicalPath(_ value: String) throws -> String {
    let normalized = value.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "\\", with: "/")
    guard !normalized.isEmpty, !normalized.hasPrefix("/"),
          !normalized.contains("\0"),
          !(normalized.count >= 2
              && normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":")
    else {
        throw CanonicalJSONError.invalidLogicalPath
    }
    let segments = normalized.split(separator: "/", omittingEmptySubsequences: false)
    guard segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
        throw CanonicalJSONError.invalidLogicalPath
    }
    return normalized
}
