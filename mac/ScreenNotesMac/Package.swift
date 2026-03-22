// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ScreenNotesMac",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "ScreenNotesMac",
      targets: ["ScreenNotesMac"]
    )
  ],
  targets: [
    .executableTarget(
      name: "ScreenNotesMac",
      path: "Sources"
    )
  ]
)
