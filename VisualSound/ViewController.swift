//
//  ViewController.swift
//  VisualSound
//
//  Created by Suman Cherukuri on 4/27/22.
//

import UIKit
import AVFoundation

class ViewController: UIViewController, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    
    @IBOutlet weak var waveView: UIView!
    
    let lineWidth = 1.0
    let recordLength = 20.0
    let xMargin = 5.0
    let sampleRate = 0.2
    
    lazy var firstPoint = CGPoint(x: xMargin, y: waveView.bounds.midY)
    lazy var lastPoint = CGPoint(x: waveView.bounds.size.width - xMargin, y: waveView.bounds.midY)
    lazy var totalSamples = Int(recordLength / sampleRate)
    lazy var sampleSpace = (lastPoint.x - firstPoint.x) / CGFloat(totalSamples)
    
    var recBezierPath: UIBezierPath?
    var playBezierPath: UIBezierPath?
    var recWaveLayer = CAShapeLayer()
    var playWaveLayer = CAShapeLayer()
    var startPoint: CGPoint!
    
    var avRecorder : AVAudioRecorder!
    var avPlayer: AVAudioPlayer!
    var meterTimer: Timer!
    let audioURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("test.mp4")
    let audioPowersURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("test.data")
    
    var audioPowers: [CGFloat] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    
    @IBAction func micButtonDown(_ sender: Any) {
        start()
    }
    
    @IBAction func micButtonUp(_ sender: Any) {
        stop()
    }
    
    @IBAction func playButtonUp(_ sender: Any) {
        play()
    }
    
    @IBAction func trashButtonUp(_ sender: Any) {
        do {
            try FileManager.default.removeItem(at: audioURL)
            try FileManager.default.removeItem(at: audioPowersURL)
            setupRecord()
        }
        catch let error as NSError {
            print("error deleting: \(error.domain)")
        }
    }
    
    func setup() {
        do {
            startPoint = firstPoint
            waveView.layer.addSublayer(recWaveLayer)
            waveView.layer.addSublayer(playWaveLayer)
            recWaveLayer.contentsCenter = waveView.frame
            recWaveLayer.fillColor = UIColor.clear.cgColor
            
            playWaveLayer.contentsCenter = waveView.frame
            playWaveLayer.fillColor = UIColor.clear.cgColor
            
            AVAudioSession.sharedInstance().requestRecordPermission { permissionGranted in
                if permissionGranted == false {
                    debugPrint("mic permission is not granted")
                    return
                }
            }
            
            let settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ] as [String: Any]
            avRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            avRecorder.delegate = self
            
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // check of there is a file already and load it
            let audioPowersData = try? Data(contentsOf: audioPowersURL)
            if audioPowersData != nil {
                let loaded: [CGFloat] = audioPowersData!.objects()
                setupRecord()
                audioPowers = loaded
                audioPowers.forEach { power in
                    drawWave(layer: recWaveLayer, path: recBezierPath!, power: power, color: UIColor.systemBlue)
                }
            }
        } catch {
            debugPrint("failed to setup: \(error.localizedDescription)")
        }
    }
    
    func setupRecord() {
        audioPowers = []
        startPoint = firstPoint
        recBezierPath = UIBezierPath(rect: waveView.bounds)
        recWaveLayer.path = recBezierPath?.cgPath
        recBezierPath!.lineWidth = lineWidth
        recWaveLayer.lineWidth = lineWidth
    }
    
    func setupPlay() {
        waveView.layer.addSublayer(playWaveLayer)
        startPoint = firstPoint
        playBezierPath = nil
        playWaveLayer.setNeedsDisplay()
        playBezierPath = UIBezierPath(rect: waveView.bounds)
        playWaveLayer.path = playBezierPath?.cgPath
        playBezierPath!.lineWidth = lineWidth
        playWaveLayer.lineWidth = lineWidth
    }
    
    func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            debugPrint("failed to start recording: \(error.localizedDescription)")
        }
        
        setupRecord()
        avRecorder.record(forDuration: recordLength)
        avRecorder.isMeteringEnabled = true
        debugPrint("Started recording: \(Date())")
        meterTimer = Timer.scheduledTimer(withTimeInterval: sampleRate, repeats: true, block: { timer in
            if self.audioPowers.count < Int(self.totalSamples) {
                self.avRecorder.updateMeters()
                let power = CGFloat(self.avRecorder.averagePower(forChannel: 0))
                self.audioPowers.append(power)
//                debugPrint("Point \(self.audioPowers.count) of \(self.totalSamples)")
                self.drawWave(layer: self.recWaveLayer, path: self.recBezierPath!, power: power, color: UIColor.systemBlue)
            }
            else {
                self.avRecorder.stop()
            }
        })
    }
    
    func stop() {
        avRecorder.stop()
        meterTimer.invalidate()
        let data = audioPowers.data
        try? data.write(to: audioPowersURL)
    }
    
    func play() {
        if avPlayer != nil && avPlayer.isPlaying {
            avPlayer.stop()
            stopPlay()
        }
        else {
            do {
                setupPlay()
                avPlayer = try AVAudioPlayer(contentsOf: audioURL)
                avPlayer.delegate = self
                avPlayer.play()
                startPoint = firstPoint
                var powerIndex = 0
                meterTimer = Timer.scheduledTimer(withTimeInterval: sampleRate, repeats: true, block: { timer in
                    if powerIndex < self.audioPowers.count {
                        self.drawWave(layer: self.playWaveLayer, path: self.playBezierPath!, power: self.audioPowers[powerIndex], color: UIColor.systemRed)
                        powerIndex += 1
                    }
                })
            }
            catch {
                debugPrint("failed play audio: \(error.localizedDescription)")
            }
        }
    }
    
    func stopPlay() {
        meterTimer.invalidate()
        avPlayer?.stop()
        avPlayer = nil
        setupPlay()
    }
    
    func drawWave(layer: CAShapeLayer, path: UIBezierPath, power: CGFloat, color: UIColor) {
        avRecorder.updateMeters()
        
        let level = max(0.2, CGFloat(power) + 50) / 2 // between 0.1 and 25
        let waveLength = CGFloat(level * (100 / 25)) // scaled to max at 100 (our height of our bar)
        
        path.move(to: startPoint)
        path.addLine(to: CGPoint(x: startPoint.x, y: startPoint.y + waveLength/2))
        path.move(to: startPoint)
        path.addLine(to: CGPoint(x: startPoint.x, y: startPoint.y - waveLength/2))
        layer.strokeColor = color.cgColor
        layer.path = path.cgPath
        waveView.setNeedsDisplay()
        startPoint = CGPoint(x: startPoint.x + sampleSpace, y: startPoint.y)
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlay()
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        debugPrint("Stopped recording: \(Date())")
        stop()
    }
}

//https://stackoverflow.com/questions/64234225/how-to-save-a-float-array-in-swift-as-txt-file
extension Array {
    var bytes: [UInt8] { withUnsafeBytes { .init($0) } }
    var data: Data { withUnsafeBytes { .init($0) } }
}

extension ContiguousBytes {
    func object<T>() -> T { withUnsafeBytes { $0.load(as: T.self) } }
    func objects<T>() -> [T] { withUnsafeBytes { .init($0.bindMemory(to: T.self)) } }
}
