import CanonicalJson
import Foundation
import Testing

@Suite("Canonical JSON")
struct CanonicalJSONTests {
    private func text(_ value: Any, keyPolicy: CanonicalJSONKeyPolicy = .none) throws -> String {
        try String(decoding: canonicalJSONData(value, keyPolicy: keyPolicy), as: UTF8.self)
    }

    @Test("keys are sorted, whitespace is dropped and slashes are not escaped")
    func sortedCompactOutput() throws {
        let value: [String: Any] = ["b": [1, true, NSNull()], "a": "x/y", "B": false]
        #expect(try text(value) == #"{"B":false,"a":"x/y","b":[1,true,null]}"#)
    }

    @Test("strings and keys are NFC-normalized")
    func unicodeNormalization() throws {
        let decomposed = "e\u{301}"
        #expect(try text([decomposed: decomposed]) == "{\"\u{e9}\":\"\u{e9}\"}")
    }

    @Test("floating point and unknown types are rejected")
    func unsupportedValues() {
        #expect(throws: CanonicalJSONError.unsupportedValue) { try canonicalJSONData(1.5) }
        #expect(throws: CanonicalJSONError.unsupportedValue) { try canonicalJSONData(Date()) }
    }

    @Test("NSNumber booleans and integers keep their JSON type")
    func nsNumberTypes() throws {
        #expect(try text([NSNumber(value: true), NSNumber(value: 7)]) == "[true,7]")
    }

    @Test("the default policy applies no key rules")
    func defaultPolicy() throws {
        #expect(try text(["timestamp": 1, "file_path": "a\\b"]) == #"{"file_path":"a\\b","timestamp":1}"#)
    }

    @Test("a key policy forbids keys and normalizes logical paths")
    func keyPolicy() throws {
        let policy = CanonicalJSONKeyPolicy(
            forbiddenKeys: ["timestamp"],
            logicalPathKeys: ["path"],
            logicalPathKeySuffixes: ["_path"]
        )
        #expect(try text(["file_path": "a\\b", "path": "c/d"], keyPolicy: policy) == #"{"file_path":"a/b","path":"c/d"}"#)
        #expect(throws: CanonicalJSONError.forbiddenKey("timestamp")) {
            try canonicalJSONData(["nested": ["timestamp": 1]], keyPolicy: policy)
        }
        for bad in ["/abs", "a/../b", "a//b", "C:/x", ""] {
            #expect(throws: CanonicalJSONError.invalidLogicalPath) {
                try canonicalJSONData(["path": bad], keyPolicy: policy)
            }
        }
    }

    @Test("the SHA-256 helper hashes the canonical bytes")
    func sha256() throws {
        let value: [String: Any] = ["b": 1, "a": 2]
        #expect(try canonicalJSONSHA256(value) == CanonicalSHA256.hexDigest(for: Data(#"{"a":2,"b":1}"#.utf8)))
    }
}
