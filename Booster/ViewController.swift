//
//  ViewController.swift
//  Booster
//
//  Created by Brennan Stehling on 8/17/17.
//  Copyright © 2017 Amazon. All rights reserved.
//

// 1) Read an audio asset to show it's sound wave [DONE]
// 2) Read an audio asset to determine the max levels [DONE]
// 3) Define a scale factor to increasing the levels to a maximum level
// 4) Build an Export Session which is used to export a new file
// 5) Display original and modified asset's sound wave

import UIKit
import AVFoundation
import BoosterKit

enum AudioActivity {
    case recording
    case playing
}

class ViewController: UIViewController {
    
    @IBOutlet weak var keysWaveformView: WaveformView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var exportButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var routeLabel: UILabel!
    
    var recorder: AVAudioRecorder!
    var player: AVAudioPlayer!
    
    var boosterPlayer: BoosterPlayer? = nil
    var boosterExporter: BoosterExporter? = nil
    var boosterWriter: BoosterWriter? = nil
    
    var inputURL: URL {
        return Bundle.main.url(forResource: "keys", withExtension: "mp3")!
    }
    
    var documentsURL: URL {
        guard let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            fatalError()
        }
        return URL(fileURLWithPath: documentsPath)
    }
    
    var outputURL: URL {
        return documentsURL.appendingPathComponent("output").appendingPathExtension("mp4")
    }
    
    var exportURL: URL {
        return documentsURL.appendingPathComponent("export").appendingPathExtension("mp4")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let waveColor = UIColor(red: 0.9569, green: 0.5255, blue: 0.1686, alpha: 1.0)
        keysWaveformView.waveColor = waveColor
        keysWaveformView.backgroundColor = UIColor.clear
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.handleRouteChange(_:)), name: NSNotification.Name.AVAudioSessionRouteChange, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let keysURL = Bundle.main.url(forResource: "keys", withExtension: "mp3")!
        updateWaveformView(assetURL: keysURL)

        refreshViews()
    }
    
    @objc func handleRouteChange(_ notification: NSNotification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshViews()
        }
    }
    
    @IBAction func recordButtonTapped(_ sender: Any) {
        if !isRecording {
            startRecording()
        }
        else {
            stopRecording()
        }
    }
    
    @IBAction func playButtonTapped(_ sender: Any) {
        if !isPlaying {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                startPlaying(assetURL: outputURL)
            }
            else {
                startPlaying(assetURL: inputURL)
            }
        }
        else {
            stopPlaying()
        }
    }
    
    @IBAction func exportButtonTapped(_ sender: Any) {
        if isExporting {
            return
        }
        debugPrint("Export")
        export()
    }
    
    func updateWaveformView(assetURL: URL) {
        keysWaveformView.asset = AVURLAsset(url: assetURL)
    }
    
    func startRecording() {
        if Thread.isMainThread {
            DispatchQueue.global().async(execute: startRecording)
            return
        }
        if FileManager.default.fileExists(atPath: exportURL.path) {
            try? FileManager.default.removeItem(at: exportURL)
        }
        prepareRecorder()
        updateAudioConfiguration(activity: .recording)
        activateAudioSession()
        recorder?.record()
        refreshViews()
    }
    
    func stopRecording() {
        if Thread.isMainThread {
            DispatchQueue.global().async(execute: stopRecording)
            return
        }
        recorder?.stop()
        deactivateAudioSession()
        refreshViews()
    }
    
    func startPlaying(assetURL: URL) {
        if Thread.isMainThread {
            DispatchQueue.global().async { [weak self] in
                self?.startPlaying(assetURL: assetURL)
            }
            return
        }
        preparePlayer(assetURL: assetURL)
        updateAudioConfiguration(activity: .playing)
        activateAudioSession()
        player?.play()
        refreshViews()
    }
    
    func stopPlaying() {
        if Thread.isMainThread {
            DispatchQueue.global().async(execute: stopPlaying)
            return
        }
        player?.stop()
        deactivateAudioSession()
        refreshViews()
    }
    
    func export() {
        let reader = BoosterReader(inputURL: outputURL)
        print("Peak: \(reader.peak)")
        print("Scale: \(reader.scale)")

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(AVAudioSessionCategorySoloAmbient, mode: AVAudioSessionModeDefault, options: [])
            try session.setActive(true)
        }
        catch {
            debugPrint("Error: \(error)")
            return
        }
        
        // writer
        
        boosterWriter = BoosterWriter(inputURL: outputURL, outputURL: exportURL, scale: reader.scale)
        boosterWriter?.write { [weak self] in
            self?.refreshViews()
        }
        
        //let reader2 = BoosterReader(inputURL: inputURL)
        
        // exporter
        
//        if FileManager.default.fileExists(atPath: outputURL.path) {
//            boosterExporter = BoosterExporter(inputURL: outputURL, outputURL: exportURL, scale: reader.scale)
//        }
//        else {
//            boosterExporter = BoosterExporter(inputURL: inputURL, outputURL: exportURL, scale: reader.scale)
//        }
//
//        boosterExporter?.export { [weak self] in
//            debugPrint("Export completed!")
//            do {
//                try session.setActive(false)
//            }
//            catch {
//                debugPrint("Error: \(error)")
//                return
//            }
//            if let error = self?.boosterExporter?.error {
//                debugPrint("Error: \(error)")
//            }
//            self?.boosterExporter = nil
//            self?.refreshViews()
//            if let assetURL = self?.exportURL {
//                self?.startPlaying(assetURL: assetURL)
//            }
//        }
        
        // player

        // retain the instance so it does not get released before completing
//        boosterPlayer = BoosterPlayer(assetURL: inputURL, scale: reader.scale)
//        boosterPlayer?.play { [weak self] in
//            do {
//                try session.setActive(false)
//            }
//            catch {
//                debugPrint("Error: \(error)")
//                return
//            }
//            self?.boosterPlayer = nil
//            self?.activityIndicator.stopAnimating()
//        }
        
        refreshViews()
    }
    
    func updateAudioConfiguration(activity: AudioActivity) {
        do {
            switch activity {
            case .recording:
                try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryRecord, mode: AVAudioSessionModeDefault, options: [.allowBluetooth])
            case .playing:
                try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, mode: AVAudioSessionModeSpokenAudio, options: [.duckOthers])
            }
        }
        catch {
            showError(error: error)
        }
    }
    
    func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        }
        catch {
            showError(error: error)
        }
    }
    
    func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        }
        catch {
            showError(error: error)
        }
    }
    
    func prepareRecorder() {
        if recorder == nil {
            let settings: [String : Any] = [
                AVFormatIDKey: UInt32(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1
            ]
            
            do {
                recorder = try AVAudioRecorder(url: outputURL, settings: settings)
                recorder.delegate = self
                recorder.prepareToRecord()
            }
            catch {
                showAlert(message: "Failure while creating audio recorder: \(error)")
            }
        }
    }
    
    func preparePlayer(assetURL: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: assetURL)
            player.delegate = self
            player.prepareToPlay()
        }
        catch {
            showAlert(message: "Failure while creating audio player: \(error)")
        }
    }
    
    var isRecording: Bool {
        return recorder?.isRecording ?? false
    }
    
    var isPlaying: Bool {
        return player?.isPlaying ?? false
    }
    
    var isExporting: Bool {
        return boosterExporter?.isExporting ?? false
    }
    
    var routeName: String {
        let input = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "Unknown"
        let output = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Unknown"
        
        if AVAudioSession.sharedInstance().category == AVAudioSessionCategoryRecord {
            return input
        }
        else if AVAudioSession.sharedInstance().category == AVAudioSessionCategoryPlayAndRecord {
            return "\(input) / \(output)"
        }
        else {
            return output
        }
    }
    
    var isBusy: Bool {
        return isPlaying || isRecording || isExporting
    }
    
    func refreshViews() {
        if !Thread.isMainThread {
            DispatchQueue.main.async(execute: refreshViews)
            return
        }
        assert(Thread.isMainThread)
        recordButton.setTitle(isRecording ? "Stop" : "Record", for: .normal)
        if isBusy {
            activityIndicator.startAnimating()
        }
        else {
            activityIndicator.stopAnimating()
        }
        
        if FileManager.default.fileExists(atPath: exportURL.path) {
            updateWaveformView(assetURL: exportURL)
        }
        else if FileManager.default.fileExists(atPath: outputURL.path) {
            updateWaveformView(assetURL: outputURL)
        }
        else {
            updateWaveformView(assetURL: inputURL)
        }
        
        routeLabel.text = routeName
    }
    
    func reportAudioSessionConfiguration() {
        let session = AVAudioSession.sharedInstance()
        debugPrint("Category: \(session.category), Mode: \(session.mode), Options: \(session.categoryOptions)")
    }
    
    func showError(error: Error) {
        showAlert(message: "Error: \(error)")
    }
    
    func showAlert(message: String) {
        assert(Thread.isMainThread)
        debugPrint(message)
        let alertController = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }
    
}

extension ViewController: AVAudioPlayerDelegate {
    
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        refreshViews()
    }
    
    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        refreshViews()
        if let error = error {
            showAlert(message: "Error: \(error)")
        }
    }
    
}

extension ViewController: AVAudioRecorderDelegate {
    
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        refreshViews()
    }
    
    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        refreshViews()
        if let error = error {
            showAlert(message: "Error: \(error)")
        }
    }
    
}
