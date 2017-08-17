//
//  BoosterExporter.swift
//  Booster
//
//  Created by Brennan Stehling on 8/30/17.
//  Copyright © 2017 Amazon. All rights reserved.
//

import Foundation
import AVFoundation

public enum BoosterExporterError: Error {
    case failure
}

// https://stackoverflow.com/questions/43951082/using-mtaudioprocessingtap-with-avassetexportsession


// Applying volume gain
// https://jeffvautin.com/2016/05/mtaudioprocessingtap-biquad-demo/

public class BoosterExporter {
    
    private let inputURL: URL
    private let outputURL: URL
    private let scale: Float
    
    private var session: AVAssetExportSession? = nil
    
    public init(inputURL: URL, outputURL: URL, scale: Float) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.scale = scale
    }
    
    public func export(completionHandler handler: @escaping () -> Swift.Void) throws {
        deleteOutput()
        
        let asset = AVAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw BoosterExporterError.failure
        }
        
        self.session = session
        
        session.canPerformMultiplePassesOverSourceMediaData = true
        session.outputURL = outputURL
        session.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration)
        session.outputFileType = AVFileTypeAppleM4A
        session.audioMix = try createAudioMix()
        session.exportAsynchronously {
            debugPrint("Done")
            DispatchQueue.main.async(execute: handler)
        }
    }
    
    // MARK: - Private -
    
    private func deleteOutput() {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try? fm.removeItem(atPath: outputURL.path)
        }
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
    
    private let tapProcess: MTAudioProcessingTapProcessCallback = {
        (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
        //print("callback \(tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut)\n")
        //let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
        //print("get audio: \(status)\n")
        print("process: \(tap) 🎺 with \(numberFrames) frames")
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
    
    private func createAudioMix() throws -> AVAudioMix? {
        let inputParameters = AVMutableAudioMixInputParameters()
        inputParameters.audioTapProcessor = try createProcessingTap()
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParameters]

        return audioMix
    }
    
}
