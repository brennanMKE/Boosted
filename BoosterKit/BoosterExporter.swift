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

public class BoosterExporter {
    
    private let inputURL: URL
    private let outputURL: URL
    private let scale: Float
    
    public private(set) var isExporting: Bool = false
    public private(set) var error: Error?
    
    private var session: AVAssetExportSession? = nil
    
    public init(inputURL: URL, outputURL: URL, scale: Float) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.scale = scale
    }
    
    public func export(completionHandler handler: @escaping () -> Swift.Void) {
        if Thread.isMainThread {
            DispatchQueue.global().async { [weak self] in
                self?.export(completionHandler: handler)
            }
            return
        }
        
        isExporting = true
        deleteOutput()
        
        let asset = AVAsset(url: inputURL)
        assert(asset.isReadable)
        assert(asset.isExportable)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            error = BoosterExporterError.failure
            DispatchQueue.main.async(execute: handler)
            return
        }
        
        let mixer = BoosterMixer(scale: scale)
        
        self.session = session
        session.canPerformMultiplePassesOverSourceMediaData = false
//        session.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmLowQualityZeroLatency
        session.outputURL = outputURL
        session.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration)
        session.outputFileType = AVFileTypeAppleM4A
        session.audioMix = mixer.audioMix
        session.exportAsynchronously { [weak self] in
            self?.isExporting = false
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
    
}
