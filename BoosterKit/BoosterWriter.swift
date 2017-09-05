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
    
    public init(inputURL: URL, outputURL: URL, scale: Float) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.scale = scale
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
    
    var writerSettings: [String : Any] {
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: AVAudioSession.sharedInstance().sampleRate,
            AVEncoderBitRateKey: 16000,
            AVNumberOfChannelsKey: 1
        ]
    }
    
    public func write(completionHandler handler: @escaping () -> Swift.Void) {
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
        assetWriter.add(writerInput)
        
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        trackOutput.alwaysCopiesSampleData = false
        assetReader.add(trackOutput)
        
        assetReader.startReading()
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: kCMTimeZero)
        
        let queue = DispatchQueue(label: "Processing Queue")
        writerInput.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let s = self else { return }
            while writerInput.isReadyForMoreMediaData {
                if assetReader.status == .reading, let inputSampleBuffer = trackOutput.copyNextSampleBuffer() {
                    s.processAudio(inputSampleBuffer: inputSampleBuffer, writerInput: writerInput, assetWriter: assetWriter)
                }
                else {
                    writerInput.markAsFinished()
                    //assert(!writerInput.isReadyForMoreMediaData)
                    
                    if assetReader.status == .completed {
                        debugPrint("Duration: \(asset.duration)")
                        assetWriter.endSession(atSourceTime: asset.duration)
                        assetWriter.finishWriting {
                            DispatchQueue.main.async(execute: handler)
                        }
                    }
                    else {
                        fatalError()
                    }
                }
            }
        }
        
        if let error = assetReader.error {
            debugPrint("Reader Error: \(error)")
        }
        
        if let error = assetWriter.error {
            debugPrint("Writer Error: \(error)")
        }
    }
    
    func processAudio(inputSampleBuffer: CMSampleBuffer, writerInput: AVAssetWriterInput, assetWriter: AVAssetWriter) {
        if let inputBlockBufferRef = CMSampleBufferGetDataBuffer(inputSampleBuffer) {
            let length = CMBlockBufferGetDataLength(inputBlockBufferRef)
            let inputBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
            let outputBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
            CMBlockBufferCopyDataBytes(inputBlockBufferRef, 0, length, inputBytes)
            // Iterate over each Int16 to check if it exceeds the current maxValue.
            (0..<length).forEach { index in
                // Pointer math
                // https://developer.apple.com/documentation/swift/unsafemutablepointer
                // Advance the pointer to the next value.
                let inputPtr = inputBytes + index
                let outputPtr = outputBytes + index
                let inputValue = inputPtr.pointee
                let outputValue = Int16(min(Float(inputValue) * scale, Float(Int16.max)))
                outputPtr.pointee = outputValue
            }
            
            // CMSampleBuffer -> CMBlockBuffer -> UnsafeMutablePointer<Int16>
            // Now how to go in the opposite direction?
            // UnsafeMutablePointer<Int16> -> CMBlockBuffer -> CMSampleBuffer
            
            // 1) CMBlockBufferCreateEmpty
            // 2) Make UnsafeMutablePointer<Int16> into UnsafeMutableRawPointer?
            // 2) CMSampleBufferCreate with CMBlockBuffer as a reference
            
            // How can a modifed buffer be appended to audioInput?
            var blockBufferRef: CMBlockBuffer?
            CMBlockBufferCreateEmpty(nil, 0, CMBlockBufferFlags(0), &blockBufferRef)
            guard let outputBlockBufferRef = blockBufferRef else { fatalError() }
            assert(CMBlockBufferIsEmpty(outputBlockBufferRef))
            let memoryBlock = UnsafeMutableRawPointer(outputBytes) // TODO: implement
            CMBlockBufferAppendMemoryBlock(outputBlockBufferRef, memoryBlock, length, nil, nil, 0, length, CMBlockBufferFlags(0))
            assert(!CMBlockBufferIsEmpty(outputBlockBufferRef))
            var sampleBuffer: CMSampleBuffer?
            
            let duration = CMSampleBufferGetDuration(inputSampleBuffer)
            let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(inputSampleBuffer)
            let decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(inputSampleBuffer)
            
            let formatDescription = CMSampleBufferGetFormatDescription(inputSampleBuffer)
            let timingInfo: [CMSampleTimingInfo] = [CMSampleTimingInfo(duration: duration, presentationTimeStamp: presentationTimeStamp, decodeTimeStamp: decodeTimeStamp)]
            let sampleSizes: [Int] = [CMBlockBufferGetDataLength(inputBlockBufferRef)]
            
            let result = CMSampleBufferCreate(
                kCFAllocatorDefault,            // allocator: CFAllocator?,
                outputBlockBufferRef,           // dataBuffer: CMBlockBuffer?,
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
            
            guard let outputSampleBuffer = sampleBuffer else {
                fatalError()
            }
            writerInput.append(outputSampleBuffer)
        }
    }
    
}
