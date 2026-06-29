import Network
import XCTest

/// Tests for the reconnect/terminate decision made after the stdio↔network
/// proxy stops. These guard the connection-reliability regression where a
/// dropped network connection (app restart, sleep/wake, Bonjour blip) caused
/// `imcp-server` to terminate instead of reconnecting — forcing the user to
/// restart their MCP client.
final class ReconnectPolicyTests: XCTestCase {

    // MARK: - reconnectDecision(for:)

    /// A dropped network connection must reconnect, not terminate. This is the
    /// primary regression: previously `.connectionClosed` returned from
    /// `MCPService.run()`, killing the process on any mid-session drop.
    func testConnectionDroppedReconnects() {
        XCTAssertEqual(reconnectDecision(for: .connectionDropped), .reconnect(after: .seconds(1)))
    }

    /// A network timeout should also reconnect rather than give up.
    func testNetworkTimedOutReconnects() {
        XCTAssertEqual(reconnectDecision(for: .networkTimedOut), .reconnect(after: .seconds(1)))
    }

    /// stdin closing means the MCP client is shutting us down — we must exit,
    /// not spin in a reconnect loop.
    func testStdinClosedTerminates() {
        XCTAssertEqual(reconnectDecision(for: .stdinClosed), .terminate)
    }

    // MARK: - proxyOutcome(for:)

    /// THE regression line: a closed network connection must be classified as a
    /// drop (→ reconnect), not left to terminate. Before the fix this mapping
    /// did not exist and `.connectionClosed` returned from `run()`.
    func testConnectionClosedMapsToConnectionDropped() {
        XCTAssertEqual(proxyOutcome(for: StdioProxyError.connectionClosed), .connectionDropped)
    }

    /// A network timeout from the proxy maps to the timed-out outcome.
    func testNetworkTimeoutMapsToNetworkTimedOut() {
        XCTAssertEqual(proxyOutcome(for: StdioProxyError.networkTimeout), .networkTimedOut)
    }

    /// Connection reset by peer (ECONNRESET) is a mid-session drop.
    func testConnectionResetMapsToConnectionDropped() {
        XCTAssertEqual(proxyOutcome(for: NWError.posix(.ECONNRESET)), .connectionDropped)
    }

    /// Socket not connected (ENOTCONN) is a mid-session drop.
    func testSocketNotConnectedMapsToConnectionDropped() {
        XCTAssertEqual(proxyOutcome(for: NWError.posix(.ENOTCONN)), .connectionDropped)
    }

    /// An unrelated network error is not a drop — it must be rethrown (nil) so
    /// the outer handler logs it loudly and applies its longer backoff.
    func testUnrelatedNWErrorRethrows() {
        XCTAssertNil(proxyOutcome(for: NWError.posix(.ETIMEDOUT)))
    }

    /// A non-network error is not a drop — rethrow (nil).
    func testGenericErrorRethrows() {
        struct DummyError: Error {}
        XCTAssertNil(proxyOutcome(for: DummyError()))
    }
}
