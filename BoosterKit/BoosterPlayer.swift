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
        
        let mixer = BoosterMixer(scale: scale)
        
        debugPrint("Asset: \(assetURL.path)")
        let playerItem = AVPlayerItem(url: assetURL)
        playerItem.audioMix = mixer.audioMix
        player = AVPlayer(playerItem: playerItem)
        if player?.status != .readyToPlay {
            if let error = player?.error {
                debugPrint("Error: \(error)")
                return
            }
        }
        
        player?.play()
        
        if let error = player?.error {
            debugPrint("Error: \(error)")
            return
        }
    }
    
    private func handlePlayerCompletion() {
        //assert(playerCompletionHandler != nil)
        removeObservers()
        if let handler = playerCompletionHandler {
            handler()
            playerCompletionHandler = nil
        }
        player = nil
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
    
}
