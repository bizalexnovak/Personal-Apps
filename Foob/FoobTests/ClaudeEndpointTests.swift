import XCTest
@testable import Foob

final class ClaudeEndpointTests: XCTestCase {
    func testInviteCodePlusURLResolvesToProxy() throws {
        let access = ClaudeEndpoint.resolveAccess(
            inviteCode: "MOM-7291",
            proxyURLOverride: "https://proxy.example.workers.dev",
            apiKey: "sk-ant-something"
        )
        guard case .proxy(let url, let code) = access else {
            return XCTFail("expected proxy access")
        }
        XCTAssertEqual(code, "MOM-7291")
        // Bare origin gets the messages path appended.
        XCTAssertEqual(url.absoluteString, "https://proxy.example.workers.dev/v1/messages")
    }

    func testInviteCodeWithoutAnyURLFallsBackToDirectKey() {
        // No baked-in default and no override → the code alone can't route.
        let access = ClaudeEndpoint.resolveAccess(
            inviteCode: "MOM-7291", proxyURLOverride: nil, apiKey: "sk-ant-x",
            defaultURL: ""
        )
        guard case .direct(let key) = access else {
            return XCTFail("expected direct access")
        }
        XCTAssertEqual(key, "sk-ant-x")
    }

    /// The shipping configuration: a friend types only an invite code, and the
    /// URL compiled into the app routes them to the proxy.
    func testInviteCodeUsesTheBakedInProxyURL() {
        let access = ClaudeEndpoint.resolveAccess(
            inviteCode: "MOM-7291", proxyURLOverride: nil, apiKey: "sk-ant-x"
        )
        guard case .proxy(let url, let code) = access else {
            return XCTFail("expected proxy access")
        }
        XCTAssertEqual(code, "MOM-7291")
        XCTAssertTrue(url.absoluteString.hasPrefix(ClaudeEndpoint.defaultProxyURL))
        XCTAssertTrue(url.absoluteString.hasSuffix("/v1/messages"))
    }

    func testKeyOnlyResolvesToDirect() {
        let access = ClaudeEndpoint.resolveAccess(
            inviteCode: nil, proxyURLOverride: nil, apiKey: "sk-ant-x"
        )
        guard case .direct = access else {
            return XCTFail("expected direct access")
        }
    }

    func testNothingConfiguredResolvesToNil() {
        XCTAssertNil(ClaudeEndpoint.resolveAccess(
            inviteCode: nil, proxyURLOverride: nil, apiKey: nil
        ))
        XCTAssertNil(ClaudeEndpoint.resolveAccess(
            inviteCode: "", proxyURLOverride: "", apiKey: ""
        ))
    }

    func testExplicitPathInOverrideIsKeptVerbatim() throws {
        let access = ClaudeEndpoint.resolveAccess(
            inviteCode: "C-1", proxyURLOverride: "https://p.example.dev/v1/messages",
            apiKey: nil
        )
        guard case .proxy(let url, _) = access else {
            return XCTFail("expected proxy access")
        }
        XCTAssertEqual(url.absoluteString, "https://p.example.dev/v1/messages")
    }
}
