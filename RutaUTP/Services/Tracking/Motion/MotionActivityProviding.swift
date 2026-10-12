import Foundation

@MainActor
protocol MotionActivityProviding: AnyObject {

    var currentActivity: DetectedMotionActivity { get }

    func start()

    func stop()

    func activities() -> AsyncStream<DetectedMotionActivity>
}
