import Foundation
import UIKit

/// Un solo vencimiento por canal. Sus callbacks usan el mismo contexto main
/// que los delegados MQTT y vuelven a comprobar el reloj en el servicio.
final class ServiceDeadlineScheduler {
    private let clock: () -> TimeInterval
    private var action: (() -> Void)?
    private var timer: Timer?
    private var deadline: TimeInterval?
    private var timerGeneration: UInt64 = 0
    private var lifecycleGeneration: UInt64 = 0
    private var observers: [NSObjectProtocol] = []

    init(clock: @escaping () -> TimeInterval) {
        self.clock = clock
    }

    func start(action: @escaping () -> Void) {
        guard self.action == nil else { return }
        self.action = action
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        observers = [UIApplication.didBecomeActiveNotification,
                     UIApplication.significantTimeChangeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.lifecycleGeneration == generation, self.action != nil else { return }
                self.cancel()
                self.action?()
            }
        }
    }

    func schedule(at next: TimeInterval?) {
        let now = clock()
        guard action != nil, let next, next.isFinite, now.isFinite else {
            cancel()
            return
        }
        if deadline == next, timer?.isValid == true { return }
        cancel()
        deadline = next
        let generation = timerGeneration
        // Un callback temprano se reprograma; evitar un bucle inmediato si
        // el reloj aún no alcanzó una frontera por unas fracciones de segundo.
        let timer = Timer(timeInterval: max(0.001, next - now), repeats: false) { [weak self] _ in
            guard let self, self.timerGeneration == generation, self.action != nil else { return }
            self.timer = nil
            self.deadline = nil
            self.action?()
        }
        timer.tolerance = 0
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timerGeneration &+= 1
        timer?.invalidate()
        timer = nil
        deadline = nil
    }

    func stop() {
        lifecycleGeneration &+= 1
        action = nil
        cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    deinit { stop() }
}
