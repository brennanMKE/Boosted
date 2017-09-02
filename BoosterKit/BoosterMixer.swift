//
//  BoosterMixer.swift
//  BoosterKit
//
//  Created by Brennan Stehling on 8/31/17.
//  Copyright © 2017 Amazon. All rights reserved.
//

import Foundation
import AVFoundation

// Applying volume gain
// https://jeffvautin.com/2016/05/mtaudioprocessingtap-biquad-demo/

public class BoosterMixer {
    
    private let scale: Float
    
    public init(scale: Float) {
        self.scale = scale
    }
    
    public var audioMix: AVAudioMix {
        guard let audioMix = try? createAudioMix() else {
            fatalError()
        }
        return audioMix
    }
    
    private func scaleVolume(bufferListInOut: UnsafeMutablePointer<AudioBufferList>) {
        let ioBuffer: AudioBufferList = bufferListInOut.pointee
        assert(ioBuffer.mNumberBuffers == 2)
        
        (0..<ioBuffer.mBuffers.mDataByteSize).forEach { index in
            debugPrint("Index: \(index)")
        }
        
        /*
        let ioPtr = UnsafeMutableAudioBufferListPointer(bufferListInOut)
        if scale != 1.0 {
            for i in 0..<ioPtr.count {
                // TODO: multiple values by scale factor
                let data = ioPtr[i].mData
                //memset(ioPtr[i].mData, 0, Int(ioPtr[i].mDataByteSize))
            }
        }
        */
        
//        let audioBuffer = bufferListInOut.pointee
//
    }
    
    // MARK: - Audio Tap -
    
    private let tapInit: MTAudioProcessingTapInitCallback = {
        (tap, clientInfo, tapStorageOut) in
        print("init: \(tap)\n")
    }
    
    private let tapFinalize: MTAudioProcessingTapFinalizeCallback = {
        (tap) in
        print("finalize: \(tap)\n")
    }
    
    private let tapPrepare: MTAudioProcessingTapPrepareCallback = {
        (tap, b, c) in
        print("prepare: \(tap, b, c)\n")
    }
    
    private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = {
        (tap) in
        print("unprepare: \(tap)\n")
    }
    
    // MTAudioProcessingTapProcessCallback = @convention(c) (MTAudioProcessingTap, CMItemCount, MTAudioProcessingTapFlags, UnsafeMutablePointer<AudioBufferList>, UnsafeMutablePointer<CMItemCount>, UnsafeMutablePointer<MTAudioProcessingTapFlags>) -> Swift.Void
    
    private let tapProcess: MTAudioProcessingTapProcessCallback = {
        (tap: MTAudioProcessingTap, numberFrames: CMItemCount, flags: MTAudioProcessingTapFlags, bufferListInOut: UnsafeMutablePointer<AudioBufferList>, numberFramesOut: UnsafeMutablePointer<CMItemCount>, flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) in
        print("process: \(tap) 🎺 with \(numberFrames) frames")
//        self?.scaleVolume(bufferListInOut: bufferListInOut)
    }
    
    private func createProcessingTap() throws -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged<AnyObject>.passUnretained(self as AnyObject).toOpaque()),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess)
        
        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        if status != noErr {
            debugPrint("Failed to create audio processing tap.")
            throw BoosterExporterError.failure
        }
        
        return tap?.takeRetainedValue()
    }
    
    private func createAudioMix() throws -> AVAudioMix {
        let inputParameters = AVMutableAudioMixInputParameters()
        inputParameters.audioTapProcessor = try createProcessingTap()
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParameters]
        
        return audioMix as AVAudioMix
    }
    
}
