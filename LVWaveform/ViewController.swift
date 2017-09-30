//
//  ViewController.swift
//  LVWaveform
//
//  Created by lvpengwei on 9/28/17.
//  Copyright © 2017 lvpengwei. All rights reserved.
//

import UIKit
import AVFoundation
import SCRecorder

class ViewController: UIViewController {

    @IBOutlet weak var waveformView: LVWaveformView!
    @IBOutlet weak var recordWaveformView: LVWaveformView!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        waveformView.delegate = self
        if let path = Bundle.main.path(forResource: "TchaikovskyExample2", ofType: "m4a") {
            let asset = AVAsset(url: URL(fileURLWithPath: path))
            waveformView.showAsset(asset)
        }
    }

    @IBAction func recordAction(_ sender: Any) {
        if recorder == nil {
            setupRecorder()
        }
        if recorder != nil {
            createSession()
            recorder?.record()
        }
    }
    
    fileprivate var recorder: SCRecorder?
    fileprivate var operation: SampleBufferProcessOperation?
    fileprivate func setupRecorder() {
        let recorder = SCRecorder()
        recorder.delegate = self
        recorder.photoConfiguration.enabled = false
        recorder.videoConfiguration.enabled = false
        do {
            try recorder.prepare()
            recorder.startRunning()
            self.recorder = recorder
        } catch let e {
            print(e)
        }
    }
    
    fileprivate func createSession() {
        let session = SCRecordSession()
        session.fileType = AVFileType.m4a.rawValue
        recorder?.session = session
    }
    
    @IBAction func stopAction(_ sender: Any) {
        recorder?.pause({ [weak self] in
            guard let s = self else { return }
            s.recorder?.session?.removeAllSegments()
        })
    }
    
}

extension ViewController: SCRecorderDelegate {
    func recorder(_ recorder: SCRecorder, didAppendAudioSampleBufferIn session: SCRecordSession) {
        
    }
    func recorder(_ recorder: SCRecorder, didAppendAudioSampleBuffer sampleBuffer: CMSampleBuffer!, in session: SCRecordSession) {
        if operation == nil {
            operation = SampleBufferProcessOperation(samplesPerPixel: Int(44100 / 80))
        }
        operation?.appendSampleBuffer(sampleBuffer)
        operation?.sampleMax = 5000
        if let time = recorder.session?.duration, let operation = operation {
            recordWaveformView.reloadData(operation, duration: CGFloat(time.seconds))
            recordWaveformView.scrollToEnd()
        }
    }
}

extension ViewController: LVWaveformViewDelegate {
    func waveformViewAssetLoadError() {
        
    }
}
