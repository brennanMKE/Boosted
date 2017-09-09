//
//  BoosterReader.swift
//  BoosterKit
//
//  Created by Brennan Stehling on 8/30/17.
//  Copyright © 2017 Amazon. All rights reserved.
//

import Foundation
import AVFoundation

public class BoosterReader {
    
    private let inputURL: URL
    public private(set) var peak: Float = 1.0
    public private(set) var scale: Float = 1.0
    
    public init(inputURL: URL) {
        self.inputURL = inputURL
        read()
    }
    
    private func read() {
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
        
        var maxValue: Int16 = 0
        while assetReader.status == .reading {
            if let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                if let blockBufferRef = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    let length = CMBlockBufferGetDataLength(blockBufferRef)
                    let sampleBytes = UnsafeMutablePointer<Int16>.allocate(capacity: length)
                    CMBlockBufferCopyDataBytes(blockBufferRef, 0, length, sampleBytes)
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
            peak = Float(maxValue) / Float(Int16.max)
            scale = Float(1.0) / peak
        }
        else {
            return
        }
    }
    
}
