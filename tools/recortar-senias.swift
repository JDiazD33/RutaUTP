// Remove only embedded side bars with native AVFoundation and Core Image.
// Build: xcrun swiftc -parse-as-library tools/recortar-senias.swift -o /tmp/recortar-senias
// Run: /tmp/recortar-senias INPUT.mp4 OUTPUT.mp4 --left 45 --right 45 --bitrate 600000
// The original is never overwritten. All video presentation times and AAC payloads
// are checked after decoding the completed output.
import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
import CryptoKit

struct CropError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func fail(_ message: String) -> CropError { CropError(message: message) }

struct DecodedVideo {
    let times: [Double]
    let width: Int
    let height: Int
}

func decodeVideo(_ url: URL) async throws -> DecodedVideo {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw fail("Missing video") }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw fail("Cannot add video decoder") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? fail("Cannot start decoder") }
    var times = [Double]()
    var width = 0
    var height = 0
    while let sample = output.copyNextSampleBuffer() {
        guard let image = CMSampleBufferGetImageBuffer(sample) else { throw fail("Missing decoded pixels") }
        width = CVPixelBufferGetWidth(image)
        height = CVPixelBufferGetHeight(image)
        times.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)))
    }
    guard reader.status == .completed, !times.isEmpty else { throw reader.error ?? fail("Video decoding incomplete") }
    return DecodedVideo(times: times, width: width, height: height)
}

func appendAudioHash(_ sample: CMSampleBuffer, hash: inout SHA256) throws {
    guard let buffer = CMSampleBufferGetDataBuffer(sample) else {
        if CMSampleBufferGetTotalSampleSize(sample) == 0 { return }
        throw fail("Missing AAC bytes")
    }
    var bytes = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(buffer))
    let status = bytes.withUnsafeMutableBytes {
        CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
    }
    guard status == kCMBlockBufferNoErr else { throw fail("Cannot read AAC bytes") }
    hash.update(data: Data(bytes))
}

func emptyAudioMarker(_ sample: CMSampleBuffer) -> [String: Any]? {
    guard CMSampleBufferGetTotalSampleSize(sample) == 0 else { return nil }
    let attachments = CMCopyDictionaryOfAttachments(allocator: nil, target: sample,
        attachmentMode: kCMAttachmentMode_ShouldPropagate)
    let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
    return ["presentationSeconds": seconds.isFinite ? seconds as Any : NSNull(),
        "numSamples": CMSampleBufferGetNumSamples(sample), "bytes": 0,
        "dataReady": CMSampleBufferDataIsReady(sample), "hasDataBuffer": CMSampleBufferGetDataBuffer(sample) != nil,
        "attachments": String(describing: attachments)]
}

// Reader buffer grouping can differ between containers. Compare each AAC sample,
// rather than a buffer's first timestamp; zero-sample drain markers have no PTS.
func individualAudioTimes(_ sample: CMSampleBuffer) throws -> [Double] {
    var result = [Double]()
    for index in 0..<CMSampleBufferGetNumSamples(sample) {
        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sample, at: index, timingInfoOut: &timing) == noErr else {
            throw fail("Cannot inspect AAC sample timing")
        }
        let time = CMTimeGetSeconds(timing.presentationTimeStamp)
        guard time.isFinite else { throw fail("Invalid AAC sample timestamp") }
        result.append(time)
    }
    return result
}

func auditAudio(_ url: URL) async throws -> (times: [Double], hash: String, emptyMarkers: [[String: Any]]) {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return ([], "", []) }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw fail("Cannot add AAC audit reader") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? fail("Cannot start AAC audit") }
    var hash = SHA256()
    var times = [Double]()
    var emptyMarkers = [[String: Any]]()
    while let sample = output.copyNextSampleBuffer() {
        try appendAudioHash(sample, hash: &hash)
        if let marker = emptyAudioMarker(sample) { emptyMarkers.append(marker) }
        times.append(contentsOf: try individualAudioTimes(sample))
    }
    guard reader.status == .completed else { throw reader.error ?? fail("AAC audit incomplete") }
    return (times, hash.finalize().map { String(format: "%02x", $0) }.joined(), emptyMarkers)
}

func crop(_ input: URL, destination: URL, left: Int, right: Int, bitRate: Int) async throws -> [String: Any] {
    guard input.standardizedFileURL != destination.standardizedFileURL else { throw fail("Original is never overwritten") }
    guard !FileManager.default.fileExists(atPath: destination.path) else { throw fail("Output already exists") }
    guard left >= 0, right >= 0, bitRate >= 50000 else { throw fail("Invalid crop or bitrate") }
    let asset = AVURLAsset(url: input)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard tracks.count == 1, let track = tracks.first else { throw fail("Expected one video track") }
    let size = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    guard transform == .identity else { throw fail("Crop expects identity orientation; rotated inputs need an explicit policy") }
    let width = Int(size.width) - left - right
    let height = Int(size.height)
    guard width > 0, width % 2 == 0, height > 0, height % 2 == 0 else {
        throw fail("Crop must leave positive even dimensions")
    }
    let fps = try await track.load(.nominalFrameRate)
    let timescale = try await track.load(.naturalTimeScale)
    let duration = try await asset.load(.duration)
    let audios = try await asset.loadTracks(withMediaType: .audio)
    guard audios.count <= 1 else { throw fail("Expected at most one audio track") }
    let reader = try AVAssetReader(asset: asset)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    writer.movieTimeScale = duration.timescale
    let videoOutput = AVAssetReaderTrackOutput(track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    videoOutput.alwaysCopiesSampleData = false
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate,
            AVVideoExpectedSourceFrameRateKey: Double(fps), AVVideoMaxKeyFrameIntervalKey: Int(ceil(Double(fps) * 2)),
            AVVideoAllowFrameReorderingKey: false, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
    ]
    guard writer.canApply(outputSettings: settings, forMediaType: .video) else { throw fail("H.264 settings unavailable") }
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    videoInput.mediaTimeScale = timescale
    videoInput.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
        sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
    guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else { throw fail("Cannot add video crop pipeline") }
    reader.add(videoOutput)
    writer.add(videoInput)
    var audioOutput: AVAssetReaderTrackOutput?
    var audioInput: AVAssetWriterInput?
    if let audio = audios.first {
        guard let format = try await audio.load(.formatDescriptions).first,
              CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC else { throw fail("Only AAC passthrough is supported") }
        let source = AVAssetReaderTrackOutput(track: audio, outputSettings: nil)
        source.alwaysCopiesSampleData = false
        let sink = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
        sink.expectsMediaDataInRealTime = false
        guard reader.canAdd(source), writer.canAdd(sink) else { throw fail("Cannot add AAC passthrough") }
        reader.add(source)
        writer.add(sink)
        audioOutput = source
        audioInput = sink
    }
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    let region = CGRect(x: left, y: 0, width: width, height: height)
    guard writer.startWriting() else { throw writer.error ?? fail("Cannot start writer") }
    writer.startSession(atSourceTime: .zero)
    guard reader.startReading() else { writer.cancelWriting(); throw reader.error ?? fail("Cannot start reader") }
    var videoFinished = false
    var audioFinished = audioInput == nil
    var videoTimes = [Double]()
    var audioTimes = [Double]()
    var emptyAudioMarkers = [[String: Any]]()
    var audioHash = SHA256()
    do {
        while !videoFinished || !audioFinished {
            var progressed = false
            if !videoFinished && videoInput.isReadyForMoreMediaData {
                if let sample = videoOutput.copyNextSampleBuffer() {
                    guard let source = CMSampleBufferGetImageBuffer(sample), let pool = adaptor.pixelBufferPool else {
                        throw fail("Missing pixels or destination buffer pool")
                    }
                    var destinationBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destinationBuffer) == kCVReturnSuccess,
                          let pixels = destinationBuffer else { throw fail("Cannot allocate cropped frame") }
                    let image = CIImage(cvPixelBuffer: source).cropped(to: region)
                        .transformed(by: CGAffineTransform(translationX: -CGFloat(left), y: 0))
                    context.render(image, to: pixels)
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    guard adaptor.append(pixels, withPresentationTime: time) else { throw writer.error ?? fail("Cannot append crop") }
                    videoTimes.append(CMTimeGetSeconds(time))
                } else { videoInput.markAsFinished(); videoFinished = true }
                progressed = true
            }
            if !audioFinished, let source = audioOutput, let sink = audioInput, sink.isReadyForMoreMediaData {
                if let sample = source.copyNextSampleBuffer() {
                    guard sink.append(sample) else { throw writer.error ?? fail("Cannot append AAC") }
                    try appendAudioHash(sample, hash: &audioHash)
                    if let marker = emptyAudioMarker(sample) { emptyAudioMarkers.append(marker) }
                    audioTimes.append(contentsOf: try individualAudioTimes(sample))
                } else { sink.markAsFinished(); audioFinished = true }
                progressed = true
            }
            if reader.status == .failed { throw reader.error ?? fail("Reader failed") }
            if writer.status == .failed { throw writer.error ?? fail("Writer failed") }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        guard reader.status == .completed else { throw reader.error ?? fail("Source did not decode completely") }
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? fail("Export did not complete") }
        let decoded = try await decodeVideo(destination)
        guard videoTimes == decoded.times, decoded.width == width, decoded.height == height else {
            throw fail("Output video frames, presentation times or dimensions differ")
        }
        let expectedAudioHash = audioInput == nil ? "" : audioHash.finalize().map { String(format: "%02x", $0) }.joined()
        let auditedAudio = try await auditAudio(destination)
        guard audioTimes == auditedAudio.times, expectedAudioHash == auditedAudio.hash else {
            throw fail("AAC audit differs: sourceSamples=\(audioTimes.count), outputSamples=\(auditedAudio.times.count), payloadHashEqual=\(expectedAudioHash == auditedAudio.hash), sourceMarkers=\(emptyAudioMarkers), outputMarkers=\(auditedAudio.emptyMarkers), sourceStart=\(audioTimes.prefix(3)), outputStart=\(auditedAudio.times.prefix(3)), sourceEnd=\(audioTimes.suffix(3)), outputEnd=\(auditedAudio.times.suffix(3))")
        }
        let exported = AVURLAsset(url: destination)
        let outputDuration = try await exported.load(.duration)
        guard CMTimeCompare(duration, outputDuration) == 0 else { throw fail("Duration changed") }
        let outputTrack = try await exported.loadTracks(withMediaType: .video)[0]
        let inputBytes = (try FileManager.default.attributesOfItem(atPath: input.path)[.size] as! NSNumber).int64Value
        let outputBytes = (try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as! NSNumber).int64Value
        return ["status": "completed", "input": input.path, "output": destination.path,
            "originalDimensions": [Int(size.width), Int(size.height)], "encodedDimensions": [width, height],
            "cropLeft": left, "cropRight": right, "cropTop": 0, "cropBottom": 0,
            "originalBytes": inputBytes, "encodedBytes": outputBytes, "requestedVideoBitrate": bitRate,
            "durationSeconds": CMTimeGetSeconds(duration), "outputDurationSeconds": CMTimeGetSeconds(outputDuration),
            "originalFPS": Double(fps), "outputFPS": Double(try await outputTrack.load(.nominalFrameRate)),
            "videoFrames": videoTimes.count, "allVideoPresentationTimesIdentical": true,
            "audioSamples": audioTimes.count, "allAudioPresentationTimesIdentical": true,
            "AACPayloadSHA256": expectedAudioHash, "AACPayloadUnchanged": true,
            "sourceEmptyAudioMarkers": emptyAudioMarkers, "outputEmptyAudioMarkers": auditedAudio.emptyMarkers,
            "playable": try await exported.load(.isPlayable), "videoPresentationTimesSeconds": videoTimes]
    } catch {
        reader.cancelReading()
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: destination)
        throw error
    }
}

@main
struct RecortarSenias {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count == 8, args[2] == "--left", args[4] == "--right", args[6] == "--bitrate",
                  let left = Int(args[3]), let right = Int(args[5]), let bitRate = Int(args[7]) else {
                throw fail("Usage: INPUT OUTPUT --left PIXELS --right PIXELS --bitrate BPS")
            }
            let report = try await crop(URL(fileURLWithPath: args[0]).standardizedFileURL,
                destination: URL(fileURLWithPath: args[1]).standardizedFileURL, left: left, right: right, bitRate: bitRate)
            guard JSONSerialization.isValidJSONObject(report) else { throw fail("Invalid JSON report") }
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
