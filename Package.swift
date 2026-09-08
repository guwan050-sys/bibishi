// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacBookPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacBookPet", targets: ["MacBookPet"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "MacBookPet",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(name: "MacBookPetTests", dependencies: ["MacBookPet"])
    ]
)
