// swift-tools-version: 5.9
//
// Vervellum builds two ways.
//
// * **macOS** builds from `Vervellum.xcodeproj`. That target compiles this package's
//   `Core` directory directly through a file-system-synchronized group, so the shared
//   code is the same source of truth without an access-control boundary to maintain.
// * **Linux** builds from this manifest: `swift build -c release --static-swift-stdlib`.
//
// The tools version is deliberately 5.9 rather than 6.x: it selects Swift 5 language
// mode, matching the Xcode project's `SWIFT_VERSION = 5.0`, so a file cannot compile
// on one platform and fail strict-concurrency checking on the other. The *toolchain*
// still needs to be Swift 6.0 or newer on Linux — the async `URLSession` methods only
// landed in swift-corelibs-foundation in 6.0.
import PackageDescription

let package = Package(
    name: "Vervellum",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VervellumKit", targets: ["VervellumKit"]),
    ],
    targets: [
        .target(name: "VervellumKit", path: "Sources/VervellumKit"),
        .testTarget(name: "VervellumKitTests",
                    dependencies: ["VervellumKit"],
                    path: "Tests/VervellumKitTests"),
    ]
)

#if os(Linux)
// The GTK front end and the executable exist only on Linux. Declaring them
// conditionally — rather than guarding their contents — keeps `swift build` on a Mac
// from needing GTK headers it will never use, and keeps the macOS project from seeing
// a target it cannot resolve.
//
// `CGtk` is a system library rather than a Swift package: the house rule is system
// frameworks only, and pkg-config already knows where GTK's headers and libraries are.
package.targets.append(
    .systemLibrary(name: "CGtk",
                   path: "Sources/CGtk",
                   pkgConfig: "gtk4",
                   providers: [.apt(["libgtk-4-dev"])])
)
package.targets.append(
    .executableTarget(name: "vervellum",
                      dependencies: ["VervellumKit"],
                      path: "Sources/vervellum")
)
package.products.append(
    .executable(name: "vervellum", targets: ["vervellum"])
)
if let kit = package.targets.first(where: { $0.name == "VervellumKit" }) {
    kit.dependencies.append(.target(name: "CGtk"))
}
#endif
