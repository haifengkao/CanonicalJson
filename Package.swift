// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CanonicalJson",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "CanonicalJson",
            targets: ["CanonicalJson"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "5.0.0"),
    ],
    targets: [
        .target(
            name: "CanonicalJson",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "CanonicalJsonTests",
            dependencies: ["CanonicalJson"]
        ),
    ]
)
