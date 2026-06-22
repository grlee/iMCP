/// Decides whether `imcp-server` should reconnect or terminate after its
/// stdio↔network proxy stops.
///
/// This is the load-bearing reliability logic: the proxy stops for several
/// distinct reasons, and only some of them mean the process should exit. A
/// dropped *network* connection (the menu bar app restarted, the machine slept,
/// a Bonjour blip) should trigger a reconnect so the MCP client keeps working
/// without a manual restart. A closed *stdin* means the MCP client itself is
/// shutting us down, so we should exit.
///
/// Extracted from `MCPService.run()` so the mapping can be unit-tested in
/// isolation (the test target cannot import the executable's top-level code).

/// Why the stdio↔network proxy stopped.
enum ProxyOutcome: Equatable {
    /// stdin reached EOF — the MCP client closed the connection and wants us to exit.
    case stdinClosed
    /// The network connection to the menu bar app dropped (reset, app quit, sleep/wake).
    case connectionDropped
    /// The network connection went silent long enough to be considered timed out.
    case networkTimedOut
}

/// What the reconnect loop should do next.
enum ReconnectDecision: Equatable {
    /// Exit the process cleanly.
    case terminate
    /// Wait `afterSeconds`, then rediscover and reconnect.
    case reconnect(afterSeconds: Double)
}

/// Maps a proxy stop reason to the loop's next action.
func reconnectDecision(for outcome: ProxyOutcome) -> ReconnectDecision {
    switch outcome {
    case .stdinClosed:
        // The MCP client closed stdin; it is shutting us down. Exit cleanly.
        return .terminate
    case .connectionDropped, .networkTimedOut:
        // The app-side connection went away, but the client is still talking to
        // us over stdio. Rediscover and reconnect so the client keeps working
        // without a manual restart.
        return .reconnect(afterSeconds: 1)
    }
}
