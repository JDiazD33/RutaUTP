import Foundation
import Darwin

/// Contadores del proceso propio, solo para una captura explícita de S10.
/// No interpreta RSS como footprint ni sustituye un perfil de pilas.
struct TrialProcessResources {
    let processID: Int
    let userMicroseconds: Int
    let systemMicroseconds: Int
    let logicalCPUs: Int

    static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["RUTAUTP_S10_TRIAL"] == "1"
            && environment["RUTAUTP_S10_RESOURCE_SAMPLING"] == "1"
    }

    static func microseconds(seconds: Int, fraction: Int) -> Int? {
        guard seconds >= 0, (0..<1_000_000).contains(fraction) else { return nil }
        let (whole, multipliedOverflow) = seconds.multipliedReportingOverflow(by: 1_000_000)
        let (value, addedOverflow) = whole.addingReportingOverflow(fraction)
        return multipliedOverflow || addedOverflow ? nil : value
    }

    static func read() -> TrialProcessResources? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0,
              let user = microseconds(seconds: Int(usage.ru_utime.tv_sec), fraction: Int(usage.ru_utime.tv_usec)),
              let system = microseconds(seconds: Int(usage.ru_stime.tv_sec), fraction: Int(usage.ru_stime.tv_usec))
        else { return nil }
        return TrialProcessResources(processID: Int(getpid()), userMicroseconds: user,
            systemMicroseconds: system, logicalCPUs: ProcessInfo.processInfo.processorCount)
    }

    var counts: [String: Int] {
        ["schemaVersion": 1, "processID": processID, "userMicroseconds": userMicroseconds,
         "systemMicroseconds": systemMicroseconds, "logicalCPUs": logicalCPUs]
    }
}
