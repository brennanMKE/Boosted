//
//  BoosterWriter.swift
//  BoosterKit
//
//  Created by Brennan Stehling on 8/31/17.
//  Copyright © 2017 Amazon. All rights reserved.
//

import Foundation
import AVFoundation

// Reference: https://github.com/ZainHaq/DownSampler

// Create an OSStatus (26, 26, 26, 1) where 26 is for A to Z.
public let kBoosterWriterError_CannotProcessSampleBuffer: OSStatus = 26 << 24 | 26 << 16 | 26 << 8 | 1

public class BoosterWriter {
    
    public init() {}
    
    public func processAsset(inputURL: URL, outputURL: URL, completionHandler handler: @escaping (_ error: Error?) -> Swift.Void) {
        read(inputURL: inputURL) { [weak self] (peak, scale, error) in
            if error != nil {
                handler(error)
            }
            else {
                self?.write(inputURL: inputURL, outputURL: outputURL, scale: scale, completionHandler: handler)
            }
        }
    }
    
    var readerSettings: [String : Any] {
        return [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsNonInterleaved: false
        ]
    }
    
    var layoutTag: AudioChannelLayoutTag {
        return kAudioChannelLayoutTag_Mono
    }
    
    var audioChannelLayoutData: Data {
        var channelLayout = AudioChannelLayout()
        channelLayout.mChannelLayoutTag = layoutTag
        let data = Data(bytes: &channelLayout, count: MemoryLayout<AudioChannelLayout>.size)
        return data
    }
    
    var writerSettings: [String : Any] {
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000,
            AVChannelLayoutKey: audioChannelLayoutData
        ]
    }
    
    private func read(inputURL: URL, completionHandler handler: @escaping (_ peak: Float, _ scale: Float, _ error: Error?) -> Swift.Void) {
        // 1) Read asset for inputURL
        // 2) Check value for each audio sample
        // 3) Compare max value to max possible value
        let asset = AVAsset(url: inputURL)
        guard let assetReader = try? AVAssetReader(asset: asset) else {
            return
        }
        
        guard let track = asset.tracks(withMediaType: AVMediaTypeAudio).first else {
            debugPrint("No audio track found in asset")
            return
        }
        
        let outputSettings: [String : Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16
        ]
        
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        assetReader.add(trackOutput)
        assetReader.startReading()
        
        let queue = DispatchQueue(label: "Reader Queue")
        queue.async { [weak self] in
            guard let strongSelf = self else { return }
            var maxValue: Int16 = 0
            while assetReader.status == .reading {
                if let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                    if let blockBufferRef = CMSampleBufferGetDataBuffer(sampleBuffer) {
                        let length = CMBlockBufferGetDataLength(blockBufferRef)
                        let sampleBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
                        guard strongSelf.checkStatus(CMBlockBufferCopyDataBytes(blockBufferRef, 0, length, sampleBytes), message: "Copying data bytes") else {
                            return
                        }
                        // Iterate over each Int16 to check if it exceeds the current maxValue.
                        (0..<length).forEach{ index in
                            // Pointer math
                            // https://developer.apple.com/documentation/swift/unsafemutablepointer
                            let ptr = sampleBytes + index
                            let value = abs(ptr.pointee)
                            if value > maxValue {
                                maxValue = value
                            }
                        }
                    }
                }
            }
            
            if assetReader.status == .completed {
                let peak = Float(maxValue) / Float(Int16.max)
                let scale = Float(1.0) / peak
                handler(peak, scale, nil)
            }
            else {
                handler(1.0, 1.0, BoosterExporterError.failure)
            }
        }
    }

    private func write(inputURL: URL, outputURL: URL, scale: Float, completionHandler handler: @escaping (_ error: Error?) -> Swift.Void) {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(atPath: outputURL.path)
        }

        let asset = AVAsset(url: inputURL)
        guard let assetReader = try? AVAssetReader(asset: asset),
            let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: AVFileTypeAppleM4A) else {
                debugPrint("Unable to create reader or writer")
                DispatchQueue.main.async {
                    handler(BoosterExporterError.failure)
                }
                return
        }
        
        guard let track = asset.tracks(withMediaType: AVMediaTypeAudio).first else {
            debugPrint("No audio track found in asset")
            DispatchQueue.main.async {
                handler(BoosterExporterError.failure)
            }
            return
        }
        
        let writerInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false
        writerInput.performsMultiPassEncodingIfSupported = false
        assetWriter.add(writerInput)
        
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        trackOutput.alwaysCopiesSampleData = false
        assetReader.add(trackOutput)
        
        assetReader.startReading()
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: kCMTimeZero)
        
        let queue = DispatchQueue(label: "Writing Queue")
        writerInput.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let s = self else { return }
            assert(writerInput.isReadyForMoreMediaData)
            
            while assetReader.status == .reading {
                if let inputSampleBuffer = trackOutput.copyNextSampleBuffer() {
                    if !s.processSampleBuffer(scale: scale, sampleBuffer: inputSampleBuffer, writerInput: writerInput) {
                        s.printReaderStatus(reader: assetReader)
                        s.printWriterStatus(writer: assetWriter)
                        DispatchQueue.main.async {
                            handler(assetReader.error ?? assetWriter.error)
                        }
                        return
                    }
                }
                else {
                    writerInput.markAsFinished()
                    
                    if assetReader.status == .completed {
                        assetWriter.endSession(atSourceTime: asset.duration)
                        assetWriter.finishWriting {
                            DispatchQueue.main.async {
                                handler(nil)
                            }
                        }
                        
                        s.printReaderStatus(reader: assetReader)
                        s.printWriterStatus(writer: assetWriter)
                    }
                    else {
                        DispatchQueue.main.async {
                            handler(BoosterExporterError.failure)
                        }
                    }
                }
            }
        }
    }
    
    func processSampleBuffer(scale: Float, sampleBuffer: CMSampleBuffer, writerInput: AVAssetWriterInput) -> Bool {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return false
        }
        let length = CMBlockBufferGetDataLength(blockBuffer)

        var sampleBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
        defer { sampleBytes.deallocate(capacity: length) }
        
        guard checkStatus(CMBlockBufferCopyDataBytes(blockBuffer, 0, length, sampleBytes), message: "Copying block buffer") else {
            return false
        }
        
        (0..<length).forEach { index in
            let ptr = sampleBytes + index
            let scaledValue = Float(ptr.pointee) * scale
            let processedValue = Int16(max(min(scaledValue, Float(Int16.max)), Float(Int16.min)))
            ptr.pointee = processedValue
        }
        
        guard checkStatus(CMBlockBufferReplaceDataBytes(sampleBytes, blockBuffer, 0, length), message: "Replacing data bytes in block buffer") else { return false }
        
        assert(CMSampleBufferIsValid(sampleBuffer))
        
        return writerInput.append(sampleBuffer)
    }

    func checkStatus(_ status: OSStatus, message: String) -> Bool {
        // See: https://www.osstatus.com/
        assert(kCMBlockBufferNoErr == noErr)
        if status != noErr {
            debugPrint("Error: \(message) [\(status)]")
        }
        return status == noErr
    }
    
    func createRawOutputFile(outputURL: URL, name: String) -> URL {
        var dataURL = outputURL.deletingLastPathComponent()
        dataURL.appendPathComponent(name)
        
        if FileManager.default.fileExists(atPath: dataURL.path) {
            try? FileManager.default.removeItem(atPath: dataURL.path)
        }
        
        FileManager.default.createFile(atPath: dataURL.path, contents: nil, attributes: nil)
        
        return dataURL
    }
    
    func printReaderStatus(reader: AVAssetReader) {
        if let error = reader.error {
            debugPrint("Reader Error: [\(reader.status.rawValue)] \(error)")
        }
    }
    
    func printWriterStatus(writer: AVAssetWriter) {
        if let error = writer.error {
            debugPrint("Writer Error: [\(writer.status.rawValue)] \(error)")
        }
    }
    
}
