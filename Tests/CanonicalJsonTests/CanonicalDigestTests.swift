import CanonicalJson
import Foundation
import Testing

@Suite("Canonical digest")
struct CanonicalDigestTests {
    @Test("primitive grammar has a stable golden vector")
    func primitiveGoldenVector() {
        var encoder = CanonicalEncoder()
        encoder.appendDomain("canonical-golden-v1")
        encoder.appendString("é")
        encoder.appendUInt64(42)
        encoder.appendInt64(-2)
        encoder.appendBool(true)
        encoder.appendOptional(nil as String?) { value, item in value.appendString(item) }
        encoder.appendArray(["b", "a"]) { value, item in value.appendString(item) }

        #expect(CanonicalSHA256.wireDigest(for: encoder) == "sha256:fdc7c5309dbf42618fe4af946a7ab7d38adb3ca6c14252ef40eda773c7956f59")
    }

    @Test("nested digest uses raw digest bytes, not the wire string")
    func nestedDigestGoldenVector() throws {
        let nested = "sha256:000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        var raw = CanonicalEncoder()
        try raw.appendNestedSHA256(wireDigest: nested)
        var forbidden = CanonicalEncoder()
        forbidden.appendString(nested)

        #expect(raw.bytes != forbidden.bytes)
        #expect(CanonicalSHA256.wireDigest(for: raw) == "sha256:1487872c8ebfff4730f0821fa6617b8f0e4d58f5b22630868ea71cc23237d757")
    }

    @Test("canonical ordering rejects duplicate encoded keys")
    func canonicalOrdering() throws {
        let sorted = try canonicalSortedUnique(["b", "a"]) { Data($0.utf8) }
        #expect(sorted == ["a", "b"])
        #expect(throws: CanonicalDigestError.duplicateCanonicalKey) {
            try canonicalSortedUnique(["a", "a"]) { Data($0.utf8) }
        }
    }

    @Test("canonical string comparator uses encoded UTF-8 bytes, not locale or scalar order")
    func canonicalStringComparatorGoldenVector() throws {
        let sorted = try canonicalSortedUnique(["aa", "b", "é", "é"]) {
            canonicalEncodedStringBytes($0)
        }
        #expect(sorted == ["b", "aa", "é", "é"])
        var encoder = CanonicalEncoder()
        encoder.appendArray(sorted) { $0.appendString($1) }
        #expect(CanonicalSHA256.wireDigest(for: encoder) == "sha256:1146753fd1678b9fd995bf100dbf59d1f164f928090166c0b750de899f16cbd6")
    }
}
