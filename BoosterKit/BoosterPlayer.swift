//
//  BoosterPlayer.swift
//  BoosterKit
//
//  Created by Brennan Stehling on 8/30/17.
//  Copyright © 2017 Amazon. All rights reserved.
//

import Foundation
import AVFoundation

public class BoosterPlayer {
    
    private let assetURL: URL
    private let scale: Float
    
    private var player: AVPlayer? = nil
    private var observers: [NSObjectProtocol] = []
    
    var playerCompletionHandler: (() -> Swift.Void)?
    
    public init(assetURL: URL, scale: Float) {
        self.assetURL = assetURL
        self.scale = scale
    }
    
    public func play(completionHandler handler: @escaping () -> Swift.Void) {
        playerCompletionHandler = handler
        addObservers()
        
        debugPrint("Asset: \(assetURL.path)")
        let playerItem = AVPlayerItem(url: assetURL)
        guard let audioMix = try? createAudioMix() else {
            fatalError()
        }
        playerItem.audioMix = audioMix
        let player = AVPlayer(playerItem: playerItem)
        if player.status != .readyToPlay {
            if let error = player.error {
                debugPrint("Error: \(error)")
                return
            }
        }
        
        player.play()
        assert(!player.isMuted)
        
        if let error = player.error {
            debugPrint("Error: \(error)")
            return
        }

        // return until it is not longer needed
        self.player = player
    }
    
    private func handlePlayerCompletion() {
        //assert(playerCompletionHandler != nil)
        removeObservers()
        if let handler = playerCompletionHandler {
            handler()
            playerCompletionHandler = nil
        }
        self.player = nil
    }
    
    // MARK: - Notifications -
    
    private func addObservers() {
        debugPrint("addObservers")
        if observers.count > 0 {
            return
        }
        
        let nc = NotificationCenter.default
        let queue: OperationQueue = OperationQueue.main
        
        observers.append(nc.addObserver(forName: NSNotification.Name.AVPlayerItemFailedToPlayToEndTime, object: nil, queue: queue, using: handlePlayerItemFailedToPlayToEndTime))
        observers.append(nc.addObserver(forName: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil, queue: queue, using: handlePlayerItemPlaybackStalled))
        observers.append(nc.addObserver(forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil, queue: queue, using: handlePlayerItemDidPlayToEndTime))
    }
    
    private func removeObservers() {
        debugPrint("removeObservers")
        if observers.count == 0 {
            return
        }
        
        let nc = NotificationCenter.default
        for observer in observers {
            nc.removeObserver(observer)
        }
        
        observers.removeAll()
    }
    
    private func handlePlayerItemFailedToPlayToEndTime(_ notification: Notification) {
        debugPrint("Player item failed to play to end time")
        if let userInfo = notification.userInfo {
            debugPrint("User Info: \(userInfo)")
        }
        handlePlayerCompletion()
    }
    
    private func handlePlayerItemPlaybackStalled(_ notification: Notification) {
        debugPrint("Player item playback stalled")
        if let userInfo = notification.userInfo {
            debugPrint("User Info: \(userInfo)")
        }
        handlePlayerCompletion()
    }
    
    private func handlePlayerItemDidPlayToEndTime(_ notification: Notification) {
        debugPrint("Player item did play to end time")
        if let userInfo = notification.userInfo {
            debugPrint("User Info: \(userInfo)")
        }
        handlePlayerCompletion()
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
        assertionFailure("Callback is never called and I do not know why.")
//        bufferListInOut.
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
