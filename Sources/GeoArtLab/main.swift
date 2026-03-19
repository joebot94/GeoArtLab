import AppKit
import Darwin

if let exitCode = MigrationParityCLI.runIfRequested(arguments: CommandLine.arguments) {
    Darwin.exit(Int32(exitCode))
}

let app = NSApplication.shared
let delegate = GeoArtLabApplication()

app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
