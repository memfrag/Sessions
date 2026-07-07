// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SessionsKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SessionsProtocol", targets: ["SessionsProtocol"]),
        .library(name: "SessionsClient", targets: ["SessionsClient"]),
        .executable(name: "sessions-server", targets: ["sessions-server"])
    ],
    targets: [
        .target(
            name: "SessionsProtocol"
        ),
        .target(
            name: "SessionsIPC",
            dependencies: ["SessionsProtocol"]
        ),
        .target(
            name: "SessionsServerCore",
            dependencies: ["SessionsProtocol", "SessionsIPC"]
        ),
        .executableTarget(
            name: "sessions-server",
            dependencies: ["SessionsServerCore", "SessionsProtocol", "SessionsIPC"]
        ),
        .target(
            name: "SessionsClient",
            dependencies: ["SessionsProtocol", "SessionsIPC"]
        ),
        .testTarget(
            name: "SessionsProtocolTests",
            dependencies: ["SessionsProtocol"]
        ),
        .testTarget(
            name: "SessionsServerCoreTests",
            dependencies: ["SessionsServerCore", "SessionsClient", "SessionsIPC", "SessionsProtocol"]
        )
    ]
)
