//
//  ProfileImageStore.swift
//  RutaUTP
//
//  Persistencia de la foto de perfil en Documents.
//  
//  Fuente ÚNICA de la foto: la leen el drawer, Perfil, el Carné Digital
//  y Datos Personales. Estaba dentro de `SideDrawer.swift`.
//  
//  CarnetImageStore conserva por separado la foto del carné físico.

import UIKit
// MARK: - Persistencia de foto de perfil (Documents)
@MainActor
enum ProfileImageStore {
    private struct FileStamp: Equatable, Sendable {
        let size: UInt64
        let modifiedAt: Date
        let fileNumber: UInt64
    }
    private struct LoadedImage: Sendable {
        let image: UIImage
        let stamp: FileStamp?
        let cost: Int
    }
    private enum ReadResult: Sendable {
        case loaded(LoadedImage), changed, unavailable
    }
    private final class CacheEntry: NSObject {
        let image: UIImage
        let stamp: FileStamp
        init(_ loaded: LoadedImage, stamp: FileStamp) {
            image = loaded.image
            self.stamp = stamp
        }
    }
    private struct PendingLoad {
        let id: UUID
        let revision: UUID
        let stamp: FileStamp?
        let cacheEpoch: UUID
        let task: Task<ReadResult, Never>
    }
    nonisolated private static let byteBudget = 16 * 1024 * 1024
    private static let cache: NSCache<NSString, CacheEntry> = {
        let cache = NSCache<NSString, CacheEntry>()
        cache.countLimit = 1
        cache.totalCostLimit = byteBudget
        return cache
    }()
    private static let cacheKey = "profile" as NSString
    private static let readQueue = DispatchQueue(label: "RutaUTP.profileImage", qos: .userInitiated)
    private static var revision = UUID()
    private static var cacheEpoch = UUID()
    private static var pending: PendingLoad?
    private static let memoryObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
    ) { _ in
        Task { @MainActor in
            cache.removeAllObjects()
            cacheEpoch = UUID()
        }
    }
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("perfil_foto.jpg")
    }

    @discardableResult
    static func save(_ image: UIImage) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            revision = UUID()
            cache.removeAllObjects()
            pending = nil
            return true
        } catch {
            return false
        }
    }

    static func load() async -> UIImage? {
        _ = memoryObserver
        let fileURL = url
        while !Task.isCancelled {
            let requestedRevision = revision
            let stamp = await inBackground { fileStamp(at: fileURL) }
            guard requestedRevision == revision else { continue }
            guard !Task.isCancelled else { return nil }
            if let stamp, let entry = cache.object(forKey: cacheKey), entry.stamp == stamp {
                return entry.image
            }
            cache.removeAllObjects()
            let request: PendingLoad
            if let existing = pending, existing.revision == requestedRevision, existing.stamp == stamp {
                request = existing
            } else {
                request = PendingLoad(id: UUID(), revision: requestedRevision, stamp: stamp,
                    cacheEpoch: cacheEpoch, task: Task {
                        await inBackground { readImage(at: fileURL, stamp: stamp) }
                    })
                pending = request
            }
            let result = await request.task.value
            guard requestedRevision == revision else { continue }
            // Una carga anterior nunca retira el registro de otra más reciente.
            if pending?.id == request.id {
                pending = nil
                if case .loaded(let loaded) = result, let stamp = loaded.stamp,
                   loaded.cost <= byteBudget, request.cacheEpoch == cacheEpoch {
                    cache.setObject(CacheEntry(loaded, stamp: stamp), forKey: cacheKey, cost: loaded.cost)
                }
            }
            guard !Task.isCancelled else { return nil }
            switch result {
            case .loaded(let loaded): return loaded.image
            case .changed: continue
            case .unavailable: return nil
            }
        }
        return nil
    }

    private static func inBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            readQueue.async { continuation.resume(returning: work()) }
        }
    }

    nonisolated private static func fileStamp(at url: URL) -> FileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let date = attributes[.modificationDate] as? Date else { return nil }
        return FileStamp(size: size.uint64Value, modifiedAt: date,
                         fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0)
    }

    nonisolated private static func imageCost(_ image: UIImage) -> Int {
        guard image.images == nil, let cgImage = image.cgImage else { return Int.max }
        let cost = cgImage.bytesPerRow.multipliedReportingOverflow(by: cgImage.height)
        return cost.overflow ? Int.max : cost.partialValue
    }

    nonisolated private static func readImage(at url: URL, stamp: FileStamp?) -> ReadResult {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return .unavailable }
        // No amplificar la memoria decodificando por adelantado fotos grandes.
        let prepared = imageCost(image) <= byteBudget ? (image.preparingForDisplay() ?? image) : image
        let currentStamp = fileStamp(at: url)
        guard currentStamp == stamp else { return .changed }
        return .loaded(LoadedImage(image: prepared, stamp: currentStamp, cost: imageCost(prepared)))
    }
}
