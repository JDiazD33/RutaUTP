// Native AVFoundation utility for sign-language clips. It never overwrites input.
// Build: xcrun swiftc -parse-as-library tools/comprimir-senias.swift -o /tmp/comprimir-senias
// Inspect: /tmp/comprimir-senias inspect input.mp4 --frames output-directory
// Encode: /tmp/comprimir-senias compress input.mp4 output.mp4 --bitrate 160000
// Validate: /tmp/comprimir-senias validate input.mp4
import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

struct ClipError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func fail(_ message: String) -> ClipError { ClipError(message: message) }

func fourCC(_ value: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xff) }
    return String(bytes: bytes, encoding: .ascii) ?? String(value)
}

func writeJSON(_ value: [String: Any]) throws {
    guard JSONSerialization.isValidJSONObject(value) else { throw fail("Non-finite or unsupported JSON metadata") }
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

func videoTrack(_ asset: AVAsset) async throws -> AVAssetTrack {
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
        throw fail("No video track")
    }
    return track
}

func inspect(_ input: URL, framesDirectory: URL?) async throws -> [String: Any] {
    let asset = AVURLAsset(url: input)
    let durationTime = try await asset.load(.duration)
    let duration = CMTimeGetSeconds(durationTime)
    let video = try await videoTrack(asset)
    let size = try await video.load(.naturalSize)
    let transform = try await video.load(.preferredTransform)
    let fps = try await video.load(.nominalFrameRate)
    let bitRate = try await video.load(.estimatedDataRate)
    let formats = try await video.load(.formatDescriptions)
    let display = CGRect(origin: .zero, size: size).applying(transform).standardized
    let audio = try await asset.loadTracks(withMediaType: .audio)
    var audioInfo = [[String: Any]]()
    for track in audio {
        let trackFormats = try await track.load(.formatDescriptions)
        var item: [String: Any] = [
            "estimatedBitrate": Double(try await track.load(.estimatedDataRate)),
            "codecs": trackFormats.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) }
        ]
        if let format = trackFormats.first,
           let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            item["sampleRate"] = description.mSampleRate
            item["channels"] = Int(description.mChannelsPerFrame)
        }
        audioInfo.append(item)
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
    var result: [String: Any] = [
        "path": input.path,
        "bytes": (attributes[.size] as? NSNumber)?.int64Value ?? 0,
        "durationSeconds": duration,
        "containerTimescale": Int(durationTime.timescale),
        "videoTimescale": Int(try await video.load(.naturalTimeScale)),
        "encodedWidth": Double(size.width),
        "encodedHeight": Double(size.height),
        "displayWidth": Double(display.width),
        "displayHeight": Double(display.height),
        "nominalFPS": Double(fps),
        "estimatedVideoBitrate": Double(bitRate),
        "videoCodecs": formats.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) },
        "preferredTransform": [Double(transform.a), Double(transform.b), Double(transform.c),
                               Double(transform.d), Double(transform.tx), Double(transform.ty)],
        "audio": audioInfo,
        "playable": try await asset.load(.isPlayable)
    ]
    if let directory = framesDirectory {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let last = max(0, duration - max(1.0 / max(Double(fps), 1), 0.05))
        let samples: [(String, Double)] = [("inicio", 0), ("mitad", duration / 2), ("final", last)]
        var extracted = [[String: Any]]()
        for (name, seconds) in samples {
            let capture = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 60000))
            let output = directory.appendingPathComponent("\(name).png")
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL,
                                                                    UTType.png.identifier as CFString,
                                                                    1, nil) else {
                throw fail("Cannot create PNG at \(output.path)")
            }
            CGImageDestinationAddImage(destination, capture.image, nil)
            guard CGImageDestinationFinalize(destination) else { throw fail("Cannot finish PNG") }
            extracted.append(["path": output.path, "requestedSeconds": seconds,
                              "actualSeconds": CMTimeGetSeconds(capture.actualTime),
                              "width": capture.image.width, "height": capture.image.height])
        }
        result["frames"] = extracted
    }
    return result
}

// Decode every video frame, rather than trusting a container header or one thumbnail.
func validate(_ input: URL) async throws -> [String: Any] {
    let asset = AVURLAsset(url: input)
    let track = try await videoTrack(asset)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw fail("Cannot add video decoder") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? fail("Cannot start video decoder") }
    var count = 0
    var first: CMTime?
    var last: CMTime?
    var lastDuration = CMTime.zero
    var monotonic = true
    var presentationTimes = [Double]()
    while let sample = output.copyNextSampleBuffer() {
        guard CMSampleBufferGetImageBuffer(sample) != nil else { throw fail("Frame has no decoded pixels") }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        if let previous = last, CMTimeCompare(time, previous) < 0 { monotonic = false }
        if first == nil { first = time }
        last = time
        lastDuration = CMSampleBufferGetDuration(sample)
        presentationTimes.append(CMTimeGetSeconds(time))
        count += 1
    }
    guard reader.status == .completed else { throw reader.error ?? fail("Decoder did not complete") }
    guard count > 0, monotonic, let first, let last else { throw fail("Invalid decoded video sequence") }
    let seconds = CMTimeGetSeconds(lastDuration)
    return ["path": input.path, "status": "completed", "decodedVideoFrames": count,
            "firstPresentationSeconds": CMTimeGetSeconds(first),
            "lastPresentationSeconds": CMTimeGetSeconds(last),
            "lastFrameDurationSeconds": seconds.isFinite ? seconds as Any : NSNull(),
            "presentationTimesSeconds": presentationTimes,
            "monotonicPresentationTimes": monotonic]
}

func compress(_ input: URL, output destination: URL, bitRate: Int) async throws -> [String: Any] {
    guard input.standardizedFileURL != destination.standardizedFileURL else {
        throw fail("Input and output must differ; the original is never overwritten")
    }
    guard !FileManager.default.fileExists(atPath: destination.path) else {
        throw fail("Output already exists: \(destination.path)")
    }
    guard bitRate >= 50000 else { throw fail("Video bitrate must be at least 50000 bits/s") }
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    let asset = AVURLAsset(url: input)
    let track = try await videoTrack(asset)
    let size = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    let fps = max(try await track.load(.nominalFrameRate), 1)
    let sourceTimescale = try await track.load(.naturalTimeScale)
    let durationTime = try await asset.load(.duration)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard audioTracks.count <= 1 else { throw fail("Multiple audio tracks need an explicit policy") }
    let reader = try AVAssetReader(asset: asset)
    let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
    if durationTime.timescale > 0 { writer.movieTimeScale = durationTime.timescale }
    writer.shouldOptimizeForNetworkUse = true
    let videoOutput = AVAssetReaderTrackOutput(track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
    videoOutput.alwaysCopiesSampleData = false
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: bitRate,
            AVVideoExpectedSourceFrameRateKey: Double(fps),
            AVVideoMaxKeyFrameIntervalKey: Int(ceil(Double(fps) * 2)),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoAllowFrameReorderingKey: false
        ]
    ]
    guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
        throw fail("H.264 settings unavailable on this system")
    }
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    videoInput.transform = transform
    if sourceTimescale > 0 { videoInput.mediaTimeScale = sourceTimescale }
    videoInput.expectsMediaDataInRealTime = false
    guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else { throw fail("Cannot add video pipeline") }
    reader.add(videoOutput)
    writer.add(videoInput)
    var audioOutput: AVAssetReaderTrackOutput?
    var audioInput: AVAssetWriterInput?
    if let audio = audioTracks.first {
        let formats = try await audio.load(.formatDescriptions)
        guard let format = formats.first,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
            throw fail("Missing audio format description")
        }
        // Audio is retained. AAC can be copied without another lossy conversion.
        guard CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC else {
            throw fail("Audio must be AAC for lossless MP4 passthrough; no audio is silently removed")
        }
        guard description.mChannelsPerFrame > 0 else { throw fail("Invalid audio channel count") }
        let source = AVAssetReaderTrackOutput(track: audio, outputSettings: nil)
        source.alwaysCopiesSampleData = false
        let sink = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
        sink.expectsMediaDataInRealTime = false
        guard reader.canAdd(source), writer.canAdd(sink) else { throw fail("Cannot add audio passthrough") }
        reader.add(source)
        writer.add(sink)
        audioOutput = source
        audioInput = sink
    }
    guard writer.startWriting() else { throw writer.error ?? fail("Cannot start encoder") }
    writer.startSession(atSourceTime: .zero)
    guard reader.startReading() else {
        writer.cancelWriting()
        throw reader.error ?? fail("Cannot start source decoder")
    }
    var videoFinished = false
    var audioFinished = audioInput == nil
    var videoSamples = 0
    var audioSamples = 0
    var originalPresentationTimes = [Double]()
    do {
        // Interleave tracks to avoid either input exhausting writer buffering.
        while !videoFinished || !audioFinished {
            var progressed = false
            if !videoFinished && videoInput.isReadyForMoreMediaData {
                if let sample = videoOutput.copyNextSampleBuffer() {
                    guard videoInput.append(sample) else { throw writer.error ?? fail("Cannot append video frame") }
                    originalPresentationTimes.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)))
                    videoSamples += 1
                } else {
                    videoInput.markAsFinished()
                    videoFinished = true
                }
                progressed = true
            }
            if !audioFinished, let source = audioOutput, let sink = audioInput, sink.isReadyForMoreMediaData {
                if let sample = source.copyNextSampleBuffer() {
                    guard sink.append(sample) else { throw writer.error ?? fail("Cannot append audio sample") }
                    audioSamples += 1
                } else {
                    sink.markAsFinished()
                    audioFinished = true
                }
                progressed = true
            }
            if writer.status == .failed { throw writer.error ?? fail("Encoder failed") }
            if reader.status == .failed { throw reader.error ?? fail("Source decoder failed") }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        guard reader.status == .completed else { throw reader.error ?? fail("Source decoder did not complete") }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? fail("Encoder did not complete") }
        let original = try await inspect(input, framesDirectory: nil)
        let encoded = try await inspect(destination, framesDirectory: nil)
        let decoded = try await validate(destination)
        guard decoded["decodedVideoFrames"] as? Int == videoSamples else {
            throw fail("Encoded frame count differs from all original samples")
        }
        guard let encodedPresentationTimes = decoded["presentationTimesSeconds"] as? [Double],
              zip(originalPresentationTimes, encodedPresentationTimes).allSatisfy({ abs($0 - $1) <= 0.000001 }) else {
            throw fail("Encoded presentation times differ from original")
        }
        let originalDuration = original["durationSeconds"] as! Double
        let encodedDuration = encoded["durationSeconds"] as! Double
        guard abs(originalDuration - encodedDuration) <= max(1.0 / Double(fps), 0.05) else {
            throw fail("Encoded duration differs from original beyond one frame")
        }
        return ["status": "completed", "requestedVideoBitrate": bitRate,
                "original": original, "encoded": encoded, "validation": decoded,
                "copiedVideoFrames": videoSamples, "copiedAudioSamples": audioSamples]
    } catch {
        reader.cancelReading()
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: destination)
        throw error
    }
}

@main
struct CompressSenias {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count >= 2 else {
                throw fail("Usage: inspect INPUT [--frames DIR] | validate INPUT | compress INPUT OUTPUT --bitrate BPS")
            }
            let input = URL(fileURLWithPath: args[1]).standardizedFileURL
            switch args[0] {
            case "inspect":
                guard args.count == 2 || (args.count == 4 && args[2] == "--frames") else {
                    throw fail("Usage: inspect INPUT [--frames DIR]")
                }
                try writeJSON(try await inspect(input, framesDirectory: args.count == 4 ? URL(fileURLWithPath: args[3]) : nil))
            case "validate":
                guard args.count == 2 else { throw fail("Usage: validate INPUT") }
                try writeJSON(try await validate(input))
            case "compress":
                guard args.count == 5, args[3] == "--bitrate", let rate = Int(args[4]) else {
                    throw fail("Usage: compress INPUT OUTPUT --bitrate BPS")
                }
                try writeJSON(try await compress(input, output: URL(fileURLWithPath: args[2]).standardizedFileURL,
                                                bitRate: rate))
            default: throw fail("Unknown command: \(args[0])")
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
