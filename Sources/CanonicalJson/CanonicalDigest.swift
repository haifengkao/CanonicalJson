import Crypto
import Foundation

public enum CanonicalDigestError: Error, Hashable, Sendable {
    case invalidSHA256WireDigest(String)
    case duplicateCanonicalKey
}

/// Builds an unambiguous byte sequence for hashing: every variable-length field is prefixed with its length as a
/// big-endian `UInt64`, so different field sequences never produce the same bytes.
public struct CanonicalEncoder: Hashable, Sendable {
    public private(set) var bytes: Data

    public init() {
        bytes = Data()
    }

    /// Appends a domain-separation tag; use a distinct tag per digest kind.
    public mutating func appendDomain(_ value: String) {
        appendString(value)
    }

    public mutating func appendString(_ value: String) {
        appendBytes(Data(value.utf8))
    }

    public mutating func appendBytes(_ value: Data) {
        appendUInt64(UInt64(value.count))
        bytes.append(value)
    }

    public mutating func appendUInt64(_ value: UInt64) {
        bytes.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init))
    }

    public mutating func appendInt64(_ value: Int64) {
        appendUInt64(UInt64(bitPattern: value))
    }

    public mutating func appendBool(_ value: Bool) {
        bytes.append(value ? 0x01 : 0x00)
    }

    public mutating func appendOptional<T>(_ value: T?, _ append: (inout Self, T) throws -> Void) rethrows {
        guard let value else {
            bytes.append(0x00)
            return
        }
        bytes.append(0x01)
        try append(&self, value)
    }

    public mutating func appendArray<T>(_ values: [T], _ append: (inout Self, T) throws -> Void) rethrows {
        appendUInt64(UInt64(values.count))
        for value in values {
            try append(&self, value)
        }
    }

    /// Appends another digest by its raw 32 bytes (not its `sha256:` string form).
    public mutating func appendNestedSHA256(wireDigest: String) throws {
        appendString("sha256")
        try appendBytes(CanonicalSHA256.rawBytes(from: wireDigest))
    }
}

public enum CanonicalSHA256 {
    /// Lowercase hex SHA-256 of `data`.
    public static func hexDigest(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `sha256:<lowercase hex>` of the encoder's bytes.
    public static func wireDigest(for encoder: CanonicalEncoder) -> String {
        "sha256:" + hexDigest(for: encoder.bytes)
    }

    /// Parses a `sha256:<64 lowercase hex>` string into its 32 raw bytes.
    public static func rawBytes(from wireDigest: String) throws -> Data {
        let prefix = "sha256:"
        guard wireDigest.hasPrefix(prefix) else {
            throw CanonicalDigestError.invalidSHA256WireDigest(wireDigest)
        }
        let hex = wireDigest.dropFirst(prefix.count)
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw CanonicalDigestError.invalidSHA256WireDigest(wireDigest)
        }
        var result = Data()
        result.reserveCapacity(32)
        var index = hex.startIndex
        for _ in 0 ..< 32 {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else {
                throw CanonicalDigestError.invalidSHA256WireDigest(wireDigest)
            }
            result.append(byte)
            index = next
        }
        return result
    }
}

/// Sorts `values` by the bytes `key` returns and throws if two values share a key.
public func canonicalSortedUnique<T>(
    _ values: [T],
    key: (T) throws -> Data
) throws -> [T] {
    let keyed = try values.map { try (value: $0, key: key($0)) }
        .sorted { $0.key.lexicographicallyPrecedes($1.key) }
    for pair in zip(keyed, keyed.dropFirst()) where pair.0.key == pair.1.key {
        throw CanonicalDigestError.duplicateCanonicalKey
    }
    return keyed.map(\.value)
}

/// The length-prefixed UTF-8 bytes of `value`, for byte-order comparison of string identifiers.
public func canonicalEncodedStringBytes(_ value: String) -> Data {
    var encoder = CanonicalEncoder()
    encoder.appendString(value)
    return encoder.bytes
}
