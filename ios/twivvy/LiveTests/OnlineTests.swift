import XCTest
import WebKit
@testable import Twivvy

/// Opt-in scheme: creates a private room with two test peers, never enters the public queue.
@MainActor final class OnlineTests: XCTestCase {
    private func waitUntil(_ description: String, seconds: Double = 35, _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for:.milliseconds(200)) }
        XCTAssertTrue(condition(), description)
        if !condition() { throw NSError(domain:"TwivvyLiveTest",code:1,userInfo:[NSLocalizedDescriptionKey:description]) }
    }
    func testPrivateRoomCommitRevealRecoveryAndRematch() async throws {
        let host = OnlineBridge(), guest = OnlineBridge()
        let window = UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        let controller = UIViewController(); window.rootViewController = controller
        for (index,bridge) in [host,guest].enumerated() {
            controller.view.addSubview(bridge.webView)
            bridge.webView.frame = CGRect(x:0,y:index*400,width:390,height:400)
        }
        window.makeKeyAndVisible()
        var room = "", hostActive = false, guestActive = false
        var hostState: [String:Any]?, guestState: [String:Any]?
        var saved: String?
        var failures: [String] = []
        var timeline: [String] = []
        host.onEvent = { type,data in
            if !["save","timer"].contains(type) { timeline.append("host: \(type), active=\(data["active"] ?? ""), reason=\(data["reason"] ?? "")") }
            if type == "room" { room = data["code"] as? String ?? "" }
            if type == "active" { hostActive = data["active"] as? Bool ?? false }
            if type == "resolved" { hostState = data["match"] as? [String:Any] }
            if type == "error" { failures.append(data["key"] as? String ?? type) }
        }
        guest.onEvent = { type,data in
            if !["save","timer"].contains(type) { timeline.append("guest: \(type), active=\(data["active"] ?? ""), reason=\(data["reason"] ?? "")") }
            if type == "active" { guestActive = data["active"] as? Bool ?? false }
            if type == "resolved" { guestState = data["match"] as? [String:Any] }
            if type == "save" { saved = data["savedJSON"] as? String }
            if type == "error" { failures.append(data["key"] as? String ?? type) }
        }
        defer {
            print(timeline.joined(separator:"\n"))
            host.send(["action":"leave"]); guest.send(["action":"leave"])
            window.isHidden = true
        }
        host.send(["action":"host","name":"iOS integration host"])
        try await waitUntil("Private room allocated") { !room.isEmpty || !failures.isEmpty }
        XCTAssertTrue(failures.isEmpty)
        guest.send(["action":"join","code":room,"name":"iOS integration guest"])
        try await waitUntil("Both WebRTC peers complete the synchronization barrier") { hostActive && guestActive }
        for peer in [host,guest] {
            _ = try await peer.webView.callAsyncJavaScript("const fail=MatchSession.prototype._fail; MatchSession.prototype._fail=function(error){window.testFailure=error.message; return fail.call(this,error);}; const apply=MatchSession.prototype._apply; MatchSession.prototype._apply=function(remote){window.testRemote=remote; return apply.call(this,remote);};",arguments:[:],in:nil,contentWorld:.page)
        }
        for (peer,dir) in [(host,1),(guest,-1)] {
            _ = try await peer.webView.callAsyncJavaScript("await window.nativeCommand(message)",arguments:["message":["action":"choose","command":["dir":dir,"platform":4]]],in:nil,contentWorld:.page)
        }
        hostActive = false; guestActive = false
        // Force the deadline only in this opt-in test; production always uses 30 seconds.
        _ = try await host.webView.callAsyncJavaScript("await session._commit()",arguments:[:],in:nil,contentWorld:.page)
        _ = try await guest.webView.callAsyncJavaScript("await session._commit()",arguments:[:],in:nil,contentWorld:.page)
        try await waitUntil("Both peers verify and resolve hidden moves") { hostState != nil && guestState != nil }
        let hostData = try JSONSerialization.data(withJSONObject:XCTUnwrap(hostState),options:.sortedKeys)
        let guestData = try JSONSerialization.data(withJSONObject:XCTUnwrap(guestState),options:.sortedKeys)
        XCTAssertEqual(hostData,guestData)
        XCTAssertEqual(hostState?["tick"] as? Int,1)
        XCTAssertEqual(hostState?["cooldown"] as? [Int],[4])
        do { try await waitUntil("Next round starts") { hostActive && guestActive } }
        catch {
            for peer in [host,guest] {
                let diagnostic = try? await peer.webView.callAsyncJavaScript("return JSON.stringify({failure:window.testFailure,localLog:session.match.log,remoteLog:window.testRemote?.log,remoteRemaining:window.testRemote?.remaining,phase:session.phase,ended:session.ended,tick:session.match.tick,pausedAt:session.pausedAt,id:session.id,plan:session._plan,channel:connection.channel?.readyState,remaining:session.remaining()})",arguments:[:],in:nil,contentWorld:.page)
                print("Protocol diagnostic: \(diagnostic ?? "none")")
            }
            throw error
        }
        guest.send(["action":"suspend"])
        try await Task.sleep(for:.seconds(1))
        let recovery = try XCTUnwrap(saved)
        _ = try await guest.webView.callAsyncJavaScript("session.dispose(); connection.closed=true; connection._stopPolling(); connection._dropPeer();",arguments:[:],in:nil,contentWorld:.page)
        let recovered = OnlineBridge()
        controller.view.addSubview(recovered.webView); recovered.webView.frame = guest.webView.frame
        var recoveredActive = false
        recovered.onEvent = { type,data in
            if type == "active" { recoveredActive = data["active"] as? Bool ?? false }
            if type == "error" { failures.append(data["key"] as? String ?? type) }
        }
        recovered.send(["action":"resume","savedJSON":recovery])
        try await waitUntil("Cold WebKit instance resumes saved credentials and history",seconds:50) { recoveredActive }
        XCTAssertTrue(failures.isEmpty,"\(failures)")
        // Exercise the existing rematch handshake with an ended session on each peer.
        for bridge in [host,recovered] {
            _ = try await bridge.webView.callAsyncJavaScript("session.finish(null)",arguments:[:],in:nil,contentWorld:.page)
        }
        hostActive = false; recoveredActive = false
        host.send(["action":"rematch"]); recovered.send(["action":"rematch"])
        try await waitUntil("Rematch reuses the connection") { hostActive && recoveredActive }
        let round = try await recovered.webView.callAsyncJavaScript("return session.match.tick",arguments:[:],in:nil,contentWorld:.page)
        XCTAssertEqual(round as? Int,0)
        recovered.send(["action":"leave"])
        host.send(["action":"leave"])
        try await Task.sleep(for:.seconds(1))
    }
}
