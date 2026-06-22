import XCTest

/// Tests for the reconnect/terminate decision made after the stdio↔network
/// proxy stops. These guard the connection-reliability regression where a
/// dropped network connection (app restart, sleep/wake, Bonjour blip) caused
/// `imcp-server` to terminate instead of reconnecting — forcing the user to
/// restart their MCP client.
final class ReconnectPolicyTests: XCTestCase {

    /// A dropped network connection must reconnect, not terminate. This is the
    /// primary regression: previously `.connectionClosed` returned from
    /// `MCPService.run()`, killing the process on any mid-session drop.
    func testConnectionDroppedReconnects() {
        XCTAssertEqual(reconnectDecision(for: .connectionDropped), .reconnect(afterSeconds: 1))
    }

    /// A network timeout should also reconnect rather than give up.
    func testNetworkTimedOutReconnects() {
        XCTAssertEqual(reconnectDecision(for: .networkTimedOut), .reconnect(afterSeconds: 1))
    }

    /// stdin closing means the MCP client is shutting us down — we must exit,
    /// not spin in a reconnect loop.
    func testStdinClosedTerminates() {
        XCTAssertEqual(reconnectDecision(for: .stdinClosed), .terminate)
    }
}
