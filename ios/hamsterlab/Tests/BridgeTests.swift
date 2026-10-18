import XCTest
import WebKit
@testable import HamsterLab

@MainActor final class BridgeTests: XCTestCase {
    func testBundledProtocolLoadsAndHashes() async throws {
        let bridge = OnlineBridge()
        let ready = expectation(description:"Bundled protocol ready")
        bridge.onEvent = { type,_ in if type == "ready" { ready.fulfill() } }
        let window = UIWindow(frame:CGRect(x:0,y:0,width:320,height:640))
        let controller = UIViewController(); window.rootViewController = controller
        controller.view.addSubview(bridge.webView); bridge.webView.frame = controller.view.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true; bridge.webView.removeFromSuperview(); bridge.webView.configuration.userContentController.removeAllScriptMessageHandlers() }
        await fulfillment(of:[ready],timeout:15)
        let value = try await bridge.webView.callAsyncJavaScript("return await sha256Hex('abc')",arguments:[:],in:nil,contentWorld:.page)
        XCTAssertEqual(value as? String,"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let rtc = try await bridge.webView.callAsyncJavaScript("const pc = new RTCPeerConnection(); const channel=pc.createDataChannel('test'); const offer=await pc.createOffer(); pc.close(); return offer.sdp.includes('m=application');",arguments:[:],in:nil,contentWorld:.page)
        XCTAssertEqual(rtc as? Bool,true)
        // NSDictionary reorders keys. The browser compares JSON histories byte-for-byte.
        let canonical = try await bridge.webView.callAsyncJavaScript("session={choose:command=>{window.testCommand=command}}; await window.nativeCommand(message); return JSON.stringify(window.testCommand)",arguments:["message":["action":"choose","command":["dir":-1,"platform":4]]],in:nil,contentWorld:.page)
        XCTAssertEqual(canonical as? String, "{\"platform\":4,\"dir\":-1}")
    }
}
