import XCTest
import RealityKit
import UIKit
import QuartzCore
@testable import HamsterLab

/// Repeatable workload for comparing scene changes on the same simulator/device.
/// Frame callbacks are diagnostic; timing thresholds would be flaky in shared CI.
final class RenderingPerformanceTests: XCTestCase {
    @MainActor func testBusyBoardRenderingBudget() async throws {
        let scene = BoardScene()
        var board = BoardState()
        for row in 0..<6 { for col in 0..<6 where board.balls.count < 12 {
            let path = TubePath(row:row,col:col,state:board)
            if let exit = path.ports.first {
                board.balls.append(Ball(id:board.balls.count+1,row:row,col:col,exit:exit))
            }
        } }
        board.nextBallId = 13
        scene.render(board,side:.bottom)
        let models = countModels(scene.anchor)
        XCTAssertLessThan(models,1000,"A 12-hamster board must stay within the render-object budget")
        let window = UIWindow(frame:UIScreen.main.bounds)
        let controller = UIViewController()
        window.rootViewController = controller
        let renderer = scene.rendererView()
        renderer.frame = controller.view.bounds
        controller.view.addSubview(renderer)
        window.makeKeyAndVisible()
        defer { renderer.removeFromSuperview(); window.isHidden = true }
        try await Task.sleep(for:.seconds(2))
        let probe = FrameProbe()
        let subscription = renderer.scene.subscribe(to:SceneEvents.Update.self) { _ in
            Task { @MainActor in probe.record() }
        }
        try await Task.sleep(for:.seconds(4))
        subscription.cancel()
        let intervals = probe.intervals.sorted()
        XCTAssertGreaterThan(intervals.count,10)
        let mean = intervals.reduce(0,+)/Double(max(1,intervals.count))
        let p95 = intervals.isEmpty ? 0 : intervals[min(intervals.count-1,Int(Double(intervals.count)*0.95))]
        let start = CACurrentMediaTime()
        for _ in 0..<12 {
            _ = Rules.resolve(&board,top:nil,bottom:nil)
            scene.render(board,side:.bottom)
        }
        let rebuild = (CACurrentMediaTime()-start)*1000/12
        print(String(format:"RENDER_BENCHMARK models=%d callbacksPerSecond=%.1f p95Milliseconds=%.2f roundRebuildMilliseconds=%.2f",models,1/mean,p95*1000,rebuild))
        XCTAssertEqual(Set(scene.hamsters.keys),Set(board.balls.map(\.id)))
    }
    @MainActor private func countModels(_ entity: Entity) -> Int {
        (entity.components[ModelComponent.self] == nil ? 0 : 1) + entity.children.reduce(0) { $0 + countModels($1) }
    }
}

@MainActor private final class FrameProbe {
    var intervals: [Double] = []
    private var previous: Double?
    func record() {
        let now = CACurrentMediaTime()
        if let previous { intervals.append(now-previous) }
        previous = now
    }
}
