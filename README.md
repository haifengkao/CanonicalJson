# CanonicalJson

Deterministic bytes for hashing and comparing structured data in Swift.

- `canonicalJSONData(_:keyPolicy:)` encodes a restricted JSON value set (`NSNull`, `Bool`, integers, `String`, arrays, `[String: Any]`) as canonical JSON: NFC-normalized strings, object keys sorted by Unicode scalar value, no whitespace, no floating point. Equal values always produce equal bytes.
- `canonicalJSONSHA256(_:keyPolicy:)` returns the lowercase hex SHA-256 of those bytes.
- `CanonicalJSONKeyPolicy` optionally forbids keys (for example volatile fields such as timestamps) and treats some keys as relative logical paths, which are validated and normalized to `/` separators.
- `CanonicalEncoder` builds an unambiguous, length-prefixed byte sequence from typed fields, and `CanonicalSHA256.wireDigest(for:)` turns it into a `sha256:<hex>` digest. Nested digests are embedded by their raw bytes.
- `canonicalSortedUnique(_:key:)` sorts by encoded key bytes and rejects duplicates; `canonicalEncodedStringBytes(_:)` gives the byte key for strings.

## Installation

```swift
.package(url: "https://github.com/haifengkao/CanonicalJson.git", from: "1.0.0")
```

Then depend on the `CanonicalJson` product. Supports macOS 13+ and iOS 16+.

## Example

```swift
import CanonicalJson

let bytes = try canonicalJSONData(["b": 1, "a": ["x", true]])
// {"a":["x",true],"b":1}

var encoder = CanonicalEncoder()
encoder.appendDomain("example-record-v1")
encoder.appendString("name")
encoder.appendUInt64(42)
let digest = CanonicalSHA256.wireDigest(for: encoder) // "sha256:…"
```

## License

MIT. See [LICENSE](LICENSE).
