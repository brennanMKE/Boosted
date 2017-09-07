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

public class BoosterWriter {
    
    private var inputURL: URL
    private var outputURL: URL
    private var scale: Float
    
    private var bypass: Bool = false
    private var simplify: Bool = true
    
    public init(inputURL: URL, outputURL: URL, scale: Float) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.scale = scale
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(atPath: outputURL.path)
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
        
        // memset is not needed with Swift?
        // https://stackoverflow.com/questions/30971278/do-i-need-to-memset-a-c-struct-in-swift
//        let size = MemoryLayout<AudioChannelLayout>.size
//        memset(&channelLayout, 0, size)
        
        channelLayout.mChannelLayoutTag = layoutTag
        let data = Data(bytes: &channelLayout, count: MemoryLayout<AudioChannelLayout>.size)
        return data
    }
    
    // kAudioFormatMPEG4AAC AVAssetWriterInput
    var writerSettings: [String : Any] {
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000,
            AVChannelLayoutKey: audioChannelLayoutData
        ]
    }
    
    public func write(completionHandler handler: @escaping (_ error: Error?) -> Swift.Void) {
        let asset = AVAsset(url: inputURL)
        guard let assetReader = try? AVAssetReader(asset: asset),
            let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: AVFileTypeAppleM4A) else {
            return
        }
        
        guard let track = asset.tracks(withMediaType: AVMediaTypeAudio).first else {
            print("No audio track found in asset")
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
        
        let beforeURL = createRawOutputFile(outputURL: outputURL, name: "before.raw")
        let afterURL = createRawOutputFile(outputURL: outputURL, name: "after.raw")
        guard let beforeFileHandle = try? FileHandle(forWritingTo: beforeURL) else { fatalError() }
        guard let afterFileHandle = try? FileHandle(forWritingTo: afterURL) else { fatalError() }

        let queue = DispatchQueue(label: "Processing Queue")
        
        writerInput.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let s = self else { return }
            assert(writerInput.isReadyForMoreMediaData)
            
            while assetReader.status == .reading {
                if let inputSampleBuffer = trackOutput.copyNextSampleBuffer() {
                    debugPrint("Read input sample buffer")
                    if !s.processAudio(inputSampleBuffer: inputSampleBuffer, writerInput: writerInput, assetWriter: assetWriter, beforeFileHandle: beforeFileHandle, afterFileHandle: afterFileHandle) {
                        s.printReaderStatus(reader: assetReader)
                        s.printWriterStatus(writer: assetWriter)
                        DispatchQueue.main.async {
                            handler(assetReader.error ?? assetWriter.error)
                        }
                        return
                    }
                }
                else {
                    debugPrint("Finished")
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
                        
                        beforeFileHandle.closeFile()
                        afterFileHandle.closeFile()
                    }
                    else {
                        fatalError()
                    }
                }
            }
        }
    }
    
    func processAudio(inputSampleBuffer: CMSampleBuffer, writerInput: AVAssetWriterInput, assetWriter: AVAssetWriter, beforeFileHandle: FileHandle, afterFileHandle: FileHandle) -> Bool {
        if var inputBlockBuffer = CMSampleBufferGetDataBuffer(inputSampleBuffer) {
            if bypass {
                if (!writerInput.append(inputSampleBuffer)) {
                    return false
                }
            }
            else {
                let length = CMBlockBufferGetDataLength(inputBlockBuffer)
                let inputBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
                let outputBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
                CMBlockBufferCopyDataBytes(inputBlockBuffer, 0, length, inputBytes)
                // Iterate over each Int16 to check if it exceeds the current maxValue.
                (0..<length).forEach { index in
                    // Pointer math
                    // https://developer.apple.com/documentation/swift/unsafemutablepointer
                    // Advance the pointer to the next value.
                    let inputPtr = inputBytes + index
                    let outputPtr = outputBytes + index
                    let inputValue = inputPtr.pointee
                    let scaled = Float(inputValue) * scale
                    // ensure value falls within range
                    let outputValue = Int16(max(min(scaled, Float(Int16.max)), Float(Int16.min)))
                    outputPtr.pointee = outputValue
                }
                
                beforeFileHandle.write(Data(bytes: inputBytes, count: length))
                afterFileHandle.write(Data(bytes: outputBytes, count: length))
                
                if simplify {
                    var blockBuffer: CMBlockBuffer?
                    CMBlockBufferCreateEmpty(nil, 0, CMBlockBufferFlags(0), &blockBuffer)
                    guard let outputBlockBuffer = blockBuffer else { fatalError() }
                    assert(CMBlockBufferIsEmpty(outputBlockBuffer))
                    let memoryBlock = UnsafeMutableRawPointer(outputBytes)
                    CMBlockBufferAppendMemoryBlock(outputBlockBuffer, memoryBlock, length, nil, nil, 0, length, CMBlockBufferFlags(0))
                    assert(!CMBlockBufferIsEmpty(outputBlockBuffer))
                    CMSampleBufferSetDataBuffer(inputSampleBuffer, outputBlockBuffer)
                    assert(CMSampleBufferIsValid(inputSampleBuffer))
                    if (!writerInput.append(inputSampleBuffer)) {
                        return false
                    }
                }
                else {
                    
                    let outputSampleBuffer = createSampleBuffer(outputBytes: outputBytes, inputSampleBuffer: inputSampleBuffer, length: length)
                    
                    assert(CMSampleBufferIsValid(outputSampleBuffer))
                    assert(CMSampleBufferGetDuration(inputSampleBuffer) == CMSampleBufferGetDuration(outputSampleBuffer))
                    assert(CMSampleBufferGetNumSamples(inputSampleBuffer) == CMSampleBufferGetNumSamples(outputSampleBuffer))
                    
                    if (!writerInput.append(outputSampleBuffer)) {
                        return false
                    }
                }
            }
        }
        
        return true
    }

    // CMSampleBuffer -> CMBlockBuffer -> UnsafeMutablePointer<Int16>
    // Now how to go in the opposite direction?
    // UnsafeMutablePointer<Int16> -> CMBlockBuffer -> CMSampleBuffer

    // 1) CMBlockBufferCreateEmpty
    // 2) Make UnsafeMutablePointer<Int16> into UnsafeMutableRawPointer?
    // 2) CMSampleBufferCreate with CMBlockBuffer as a reference

    func createSampleBuffer(outputBytes: UnsafeMutablePointer<Int16>, inputSampleBuffer: CMSampleBuffer, length: Int) -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateEmpty(nil, 0, CMBlockBufferFlags(0), &blockBuffer)
        guard let outputBlockBuffer = blockBuffer else { fatalError() }
        assert(CMBlockBufferIsEmpty(outputBlockBuffer))
        let memoryBlock = UnsafeMutableRawPointer(outputBytes)
        CMBlockBufferAppendMemoryBlock(outputBlockBuffer, memoryBlock, length, nil, nil, 0, length, CMBlockBufferFlags(0))
        assert(!CMBlockBufferIsEmpty(outputBlockBuffer))
        var sampleBuffer: CMSampleBuffer?
        
        let duration = CMSampleBufferGetDuration(inputSampleBuffer)
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(inputSampleBuffer)
        let decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(inputSampleBuffer)
        
        let formatDescription = CMSampleBufferGetFormatDescription(inputSampleBuffer)
        let timingInfo: [CMSampleTimingInfo] = [CMSampleTimingInfo(duration: duration, presentationTimeStamp: presentationTimeStamp, decodeTimeStamp: decodeTimeStamp)]
        var sampleSizes: [CMItemCount] = []
        CMSampleBufferGetSampleSizeArray(inputSampleBuffer, 0, nil, &sampleSizes)
        
        let result = CMSampleBufferCreate(
            kCFAllocatorDefault,            // allocator: CFAllocator?,
            outputBlockBuffer,           // dataBuffer: CMBlockBuffer?,
            true,                           // dataReady: Boolean,
            nil,                            // makeDataReadyCallback: CMSampleBufferMakeDataReadyCallback?,
            nil,                            // makeDataReadyRefcon: UnsafeMutablePointer<Void>,
            formatDescription,              // formatDescription: CMFormatDescription?,
            1,                              // numSamples: CMItemCount,
            timingInfo.count,               // numSampleTimingEntries: CMItemCount,
            timingInfo,                     // sampleTimingArray: UnsafePointer<CMSampleTimingInfo>,
            sampleSizes.count,              // numSampleSizeEntries: CMItemCount,
            sampleSizes,                    // sampleSizeArray: UnsafePointer<Int>,
            &sampleBuffer                   // sBufOut: UnsafeMutablePointer<Unmanaged<CMSampleBuffer>?>
        )
        
        if result != noErr {
            fatalError()
        }
        
        guard let resultSampleBuffer = sampleBuffer else {
            fatalError()
        }
        
        return resultSampleBuffer
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
        switch reader.status {
        case .unknown:
            debugPrint("Reader Status: unknown")
        case .reading:
            debugPrint("Reader Status: reading")
        case .completed:
            debugPrint("Reader Status: completed")
        case .failed:
            debugPrint("Reader Status: failed")
        case .cancelled:
            debugPrint("Reader Status: cancelled")
        }
        if let error = reader.error {
            debugPrint("Reader Error: \(error)")
        }
    }
    
    func printWriterStatus(writer: AVAssetWriter) {
        switch writer.status {
        case .unknown:
            debugPrint("Writer Status: unknown")
        case .writing:
            debugPrint("Writer Status: writing")
        case .completed:
            debugPrint("Writer Status: completed")
        case .failed:
            debugPrint("Writer Status: failed")
        case .cancelled:
            debugPrint("Writer Status: cancelled")
        }
        if let error = writer.error {
            debugPrint("Writer Error: \(error)")
        }
    }
    
}
