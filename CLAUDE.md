# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

iMCP is a macOS menu bar app that exposes your macOS data (Calendar, Contacts, Location, Maps, Messages, Reminders, Weather, Shortcuts) to AI clients over the [Model Context Protocol](https://modelcontextprotocol.io). It ships as a single `.app` that bundles a CLI executable, `imcp-server`.

## Build, lint, test

All commands run from the repo root and target the `iMCP` Xcode project (there is no `Package.swift` — SPM dependencies are managed through the `.xcodeproj`).

```bash
# Build (matches CI)
xcodebuild -quiet -scheme iMCP -configuration Debug -destination "platform=macOS" build

# Lint (CI runs this with --strict and fails on any finding)
swift format lint --strict --recursive .

# Auto-format in place (run before committing)
swift format -i -r .

# Run tests (the imcp-server / CLI test target)
xcodebuild test -scheme imcp-serverTests -destination "platform=macOS"
```

Requirements: macOS 15+ deployment target; CI builds on macOS 26 / Xcode 26. The `.swift-format` config uses 4-space indent, 120 line length, and `lineBreakBeforeEachArgument`.

## Architecture: two cooperating processes

The defining design choice is the split between the **app** and the **CLI**, which communicate over the local network rather than in-process:

- **`App/`** (`iMCP.app`) — a sandboxed SwiftUI `MenuBarExtra` app. It owns all macOS permission prompts and framework access (EventKit, Contacts, CoreLocation, MapKit, WeatherKit, etc.) and runs the actual `MCP.Server`. Entry point: `App/App.swift`.
- **`CLI/main.swift`** (`imcp-server`) — the executable MCP clients actually launch. It is a **stdio↔TCP proxy**: `StdioProxy` (an actor) reads JSON-RPC from `stdin`, relays it to the app over an `NWConnection`, and writes responses back to `stdout`. It finds the app via Bonjour (`NWBrowser`).

The two halves discover each other by both advertising/browsing a Bonjour service of type `_mcp._tcp` in domain `local.` (`acceptLocalOnly`, IPv4, no peer-to-peer). This is why an MCP client config points at `/Applications/iMCP.app/Contents/MacOS/imcp-server`, not at a port.

### Server side (`App/Controllers/ServerController.swift`)

This single file holds most of the app's runtime logic:
- `ServerController` (`@MainActor`, ObservableObject) — the bridge between SwiftUI and the network layer; manages server status, the connection-approval UI flow, and the **trusted clients** allowlist (persisted in `AppStorage`, auto-approves known clients).
- `ServerNetworkManager` (actor) — owns the `NWListener`/`NWBrowser`, accepts connections, and spins up a per-connection `MCP.Server`.
- `ServiceRegistry` — the catalog of available services and the source of truth for which tools exist.

### Services and tools

- **`Service`** (`App/Models/Service.swift`) — protocol each capability conforms to. Implemented as singletons (`SomeService.shared`). A service exposes `@ToolBuilder var tools: [Tool]` and optionally `isActivated`/`activate()` for permission handling. `ToolBuilder` is a `@resultBuilder` so tools are declared as a list literal.
- **`Tool`** (`App/Models/Tool.swift`) — wraps a `name`, `description`, `JSONSchema` input schema, MCP `annotations`, and an async `implementation` closure. The init encodes the closure's `Encodable` return value to JSON and decodes it into an MCP `Value`, applying the current time zone — so tool implementations just return ordinary `Encodable` types (often `Ontology` schema.org-style types).
- Concrete services live in `App/Services/` (one file each: `Calendar.swift`, `Contacts.swift`, `Weather.swift`, …).

### Adding or changing a service

When adding a service you must touch **both** registration points in `ServerController.swift`, or the tool will work but have no UI toggle (or vice versa):
1. Create `App/Services/YourService.swift` conforming to `Service` with a `.shared` singleton and tools built via `@ToolBuilder`.
2. Add it to `ServiceRegistry.services` (exposes the tools to the MCP server).
3. Add a `ServiceConfig` entry in `ServiceRegistry.configureServices(...)` and a corresponding `Binding<Bool>` parameter (drives the menu UI toggle and `@AppStorage` persistence).

## Project-specific gotchas

- **WeatherKit is conditionally compiled** behind the `WEATHERKIT_AVAILABLE` Swift compilation flag (requires the WeatherKit entitlement / paid signing). `WeatherService` is only registered when that flag is set; expect builds without it to omit Weather.
- **CLI `ServiceGroup` configuration is load-bearing.** `CLITests/ServiceGroupConfigurationTests.swift` guards a past fatal crash: services in `CLI/main.swift` must use `successTerminationBehavior: .gracefullyShutdownGroup` (not the library default `.cancelGroup`), because `MCPService.run()` returns normally when the Bonjour connection drops. Don't "simplify" this away.
- **iMessage access** uses the [Madrid](https://github.com/loopwork-ai/madrid) package to read `~/Library/Messages/chat.db` (Apple's proprietary `typedstream` format). The sandbox only gains access after the user picks the file via `NSOpenPanel` when enabling the Messages service.
- **SourceKit false positives**: per `.cursor/rules/`, ignore spurious "Cannot find type" / "No such module" warnings — assume types/modules exist. Do not add new SPM packages without explicit need.

## Key dependencies

MCP is provided by the official [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) (`MCP`), which this project originated. Other notable packages: `Ontology` (schema.org return types), `JSONSchema` (tool input schemas), `Madrid` (iMessage), `MenuBarExtraAccess` (menu bar UX), and `swift-service-lifecycle` (`ServiceGroup` in the CLI).

## Release

`Scripts/release.sh` runs the full Developer ID build/archive/export/notarize/staple/tag/upload pipeline (run `Scripts/release.sh` with no args for `all`, or a subcommand like `check`, `archive`, `notarize`). Releases are also distributed via Homebrew cask `mattt/tap/iMCP`.
