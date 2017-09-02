//
//  BoosterWriter.swift
//  BoosterKit
//
//  Created by Brennan Stehling on 8/31/17.
//  Copyright © 2017 Amazon. All rights reserved.
//

import Foundation
import AVFoundation

//Reference: https://github.com/ZainHaq/DownSampler

public class BoosterWriter {
    
    private var inputURL: URL
    private var outputURL: URL
    private var scale: Float
    
    public init(inputURL: URL, outputURL: URL, scale: Float) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.scale = scale
    }
    
    public func write(completionHandler handler: @escaping () -> Swift.Void) {
        let asset = AVAsset(url: inputURL)
        guard let assetReader = try? AVAssetReader(asset: asset),
            let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: AVFileTypeAppleM4A) else {
            return
        }
        
        // AVLinearPCMIsNonInterleaved
        
        guard let track = asset.tracks(withMediaType: AVMediaTypeAudio).first else {
            print("No audio track found in asset")
            return
        }
        
        let outputSettings: [String : Any] = [
//            AVFormatIDKey: Int(kAudioFormatLinearPCM),
//            AVLinearPCMIsBigEndianKey: false,
//            AVLinearPCMIsFloatKey: false,
//            AVLinearPCMBitDepthKey: 16,
//            AVSampleRateKey: AVAudioSession.sharedInstance().sampleRate,
//            AVLinearPCMIsNonInterleaved: false
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: AVAudioSession.sharedInstance().sampleRate,
            AVEncoderBitRateKey: 16000,
            AVNumberOfChannelsKey: 1
        ]
        
        let readerSettings: [String : Any] = [AVFormatIDKey: Int(kAudioFormatLinearPCM)]
        
        let audioInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: outputSettings)
        audioInput.expectsMediaDataInRealTime = false
        
        assetWriter.add(audioInput)
        
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        trackOutput.alwaysCopiesSampleData = false
        assetReader.add(trackOutput)
        
        assetReader.startReading()
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: kCMTimeZero)
        
        let queue = DispatchQueue(label: "Downsample Queue")
        audioInput.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let s = self else { return }
            while audioInput.isReadyForMoreMediaData {
                while assetReader.status == .reading {
                    if let inputSampleBuffer = trackOutput.copyNextSampleBuffer() {
                        if let inputBlockBufferRef = CMSampleBufferGetDataBuffer(inputSampleBuffer) {
                            let length = CMBlockBufferGetDataLength(inputBlockBufferRef)
                            let inputBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
                            let outputBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
                            CMBlockBufferCopyDataBytes(inputBlockBufferRef, 0, length, inputBytes)
                            // Iterate over each Int16 to check if it exceeds the current maxValue.
                            (0..<length).forEach { index in
                                // Pointer math
                                // https://developer.apple.com/documentation/swift/unsafemutablepointer
                                let inputPtr = inputBytes + index
                                let outputPtr = outputBytes + index
                                let inputValue = inputPtr.pointee
                                let outputValue = Int16(min(Float(inputValue) * s.scale, Float(Int16.max)))
                                outputPtr.pointee = outputValue
//                                debugPrint("\(inputValue) -> \(outputValue)")
                            }
                            
                            // CMSampleBuffer -> CMBlockBuffer -> UnsafeMutablePointer<Int16>
                            // Now how to go in the opposite direction?
                            // UnsafeMutablePointer<Int16> -> CMBlockBuffer -> CMSampleBuffer
                            
                            // 1) CMBlockBufferCreateEmpty
                            // 2) Make UnsafeMutablePointer<Int16> into UnsafeMutableRawPointer? (or can it be used directly?)
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
                            
                            let numSamples = CMSampleBufferGetNumSamples(inputSampleBuffer)
                            
                            // Crashing error here! Why?
                            CMSampleBufferCreate(kCFAllocatorDefault, outputBlockBufferRef, true, nil, nil, nil, numSamples, 1, nil, length, nil, &sampleBuffer)
                            
//                            inputSampleBuffer
                            
                            /*
                             allocator: CFAllocator,
                             dataBuffer: CMBlockBuffer,
                             dataReady: Bool,
                             makeDataReadyCallback: CMSampleBufferMakeDataReady,
                             makeDataReadyRefcon: CMSampleBufferMakeDataReady,
                             formatDescription: CMSampleBufferMakeDataReady,
                             formatDescription: Dictionary,
                             numSamples: Int,
                             numSampleTimingEntries: Int,
                             sampleTimingArray: CMSampleTimingInfo,
                             numSampleSizeEntries: Int,
                             sampleSizeArray: Array,
                             sBufOut: CMSampleBuffer
                             */
                            
//                            CMSampleBufferGet


 
                            guard let outputSampleBuffer = sampleBuffer else { fatalError() }
                            audioInput.append(outputSampleBuffer)
                        }
                    }
                }
                
                if assetReader.status == .completed {
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
    
}
