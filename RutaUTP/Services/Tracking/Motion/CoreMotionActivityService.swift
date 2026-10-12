import Foundation
import CoreMotion

@MainActor
final class CoreMotionActivityService:
    MotionActivityProviding {

    private let manager = CMMotionActivityManager()
    private let operationQueue = OperationQueue.main

    private var continuation:
        AsyncStream<DetectedMotionActivity>.Continuation?

    private var stream:
        AsyncStream<DetectedMotionActivity>?

    private var isRunning = false
    private var generation = UUID()

    private(set) var currentActivity:
        DetectedMotionActivity = .unknown

    func start() {
        guard !isRunning else {
            return
        }

        guard CMMotionActivityManager.isActivityAvailable() else {
            currentActivity = .unknown
            continuation?.yield(.unknown)

            #if DEBUG
            print("[CoreMotion] Actividad física no disponible")
            #endif

            return
        }

        prepareStreamIfNeeded()
        isRunning = true
        let token = UUID()
        generation = token

        manager.startActivityUpdates(
            to: operationQueue
        ) { [weak self] activity in
            guard
                let activity
            else {
                return
            }

            let detected = Self.map(activity)

            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.generation == token else { return }
                self.currentActivity = detected
                self.continuation?.yield(detected)

                #if DEBUG
                print(
                    "[CoreMotion] Actividad detectada: " +
                    detected.rawValue
                )
                #endif
            }
        }
    }

    func stop() {
        generation = UUID()
        guard isRunning else {
            return
        }

        manager.stopActivityUpdates()
        isRunning = false

        continuation?.finish()
        continuation = nil
        stream = nil

        currentActivity = .unknown

        #if DEBUG
        print("[CoreMotion] Monitoreo detenido")
        #endif
    }

    func activities()
        -> AsyncStream<DetectedMotionActivity> {
        prepareStreamIfNeeded()

        guard let stream else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return stream
    }

    private func prepareStreamIfNeeded() {
        guard stream == nil else {
            return
        }

        stream = AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            self.continuation = continuation
            continuation.yield(self.currentActivity)
        }
    }

    nonisolated private static func map(
        _ activity: CMMotionActivity
    ) -> DetectedMotionActivity {
        guard activity.confidence != .low else {
            return .unknown
        }

        if activity.automotive {
            return .automotive
        }

        if activity.cycling {
            return .cycling
        }

        if activity.running {
            return .running
        }

        if activity.walking {
            return .walking
        }

        if activity.stationary {
            return .stationary
        }

        return .unknown
    }
}
