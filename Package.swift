// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KimoCalendar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "KimoCalendar", targets: ["KimoCalendar"])],
    targets: [
        .target(name: "KimoCalendarCore"),
        .executableTarget(
            name: "KimoCalendar",
            dependencies: ["KimoCalendarCore"],
            resources: [.copy("Resources/Holidays")]
        ),
        .testTarget(name: "KimoCalendarCoreTests", dependencies: ["KimoCalendarCore"]),
    ]
)
