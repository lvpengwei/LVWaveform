//
//  LVWaveformView.swift
//  LVWaveform
//
//  Created by lvpengwei on 9/28/17.
//  Copyright © 2017 lvpengwei. All rights reserved.
//

import UIKit
import AVFoundation
import Accelerate

protocol LVWaveformViewDelegate: class {
    func waveformViewAssetLoadError()
}

class LVWaveformView: UIView {
    
    weak var delegate: LVWaveformViewDelegate?
    var widthPerSec: CGFloat = 60 // 每一秒的宽度
    var samplePerSec: Int = 80 // (60 / 0.75)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    fileprivate weak var scrollView: WaveformScrollView!
    fileprivate func commonInit() {
        let scrollView = WaveformScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        self.scrollView = scrollView
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
    }
    
    fileprivate var asset: AVAsset? = nil
    func showAsset(_ asset: AVAsset) {
        self.asset = asset
        loadAsset(asset) { [weak self] (b) in
            guard let s = self else { return }
            if b {
                s.calc()
            } else {
                DispatchQueue.main.async {
                    s.delegate?.waveformViewAssetLoadError()
                }
            }
        }
    }

    fileprivate func calc() {
        guard
            let asset = self.asset,
            let assetTrack = asset.tracks(withMediaType: .audio).first,
            let formatDescriptions = assetTrack.formatDescriptions as? [CMAudioFormatDescription],
            let audioFormatDesc = formatDescriptions.first,
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc)
            else { return }
        
        guard let reader = try? AVAssetReader(asset: asset) else { return }
        let outputSettingsDict: [String : Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: assetTrack, outputSettings: outputSettingsDict)
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)
        
        var channelCount = 1
        for item in formatDescriptions {
            guard let fmtDesc = CMAudioFormatDescriptionGetStreamBasicDescription(item) else {
                return
            }
            channelCount = Int(fmtDesc.pointee.mChannelsPerFrame)
        }
        let samplesPerPixel = max(1, channelCount * Int(asbd.pointee.mSampleRate / Float64(samplePerSec)))
        let operation = SampleBufferProcessOperation(samplesPerPixel: samplesPerPixel)
        // 16-bit samples
        reader.startReading()
        defer { reader.cancelReading() } // Cancel reading if we exit early if operation is cancelled
        
        while reader.status == .reading {
            guard let readSampleBuffer = readerOutput.copyNextSampleBuffer() else {
                break
            }
            // Append audio sample buffer into our current sample buffer
            operation.appendSampleBuffer(readSampleBuffer)
            CMSampleBufferInvalidate(readSampleBuffer)
        }
        
        // Process the remaining samples at the end which didn't fit into samplesPerPixel
        operation.processRemaining()
        
        if reader.status == .completed {
            DispatchQueue.main.async {
                self.reloadData(operation, duration: CGFloat(asset.duration.seconds))
            }
        } else {
            print("LVWaveformView failed to read audio: \(String(describing: reader.error))")
        }
    }
    
    func reloadData(_ operation: SampleBufferProcessOperation, duration: CGFloat) {
        scrollView.sampleMax = operation.sampleMax
        scrollView.contentSize = CGSize(width: duration * widthPerSec, height: bounds.height)
        scrollView.drawSamples(operation.outputSamples)
    }
    
    func scrollToEnd() {
        DispatchQueue.main.async {
            self.scrollView.contentOffset = CGPoint(x: max(0, self.scrollView.contentSize.width - self.scrollView.bounds.width), y: 0)
        }
    }
    
    fileprivate func loadAsset(_ asset: AVAsset, _ completion: @escaping ((Bool)->Void)) {
        var error: NSError?
        var error1: NSError?
        if asset.statusOfValue(forKey: "tracks", error: &error) == .loaded && asset.statusOfValue(forKey: "duration", error: &error1) == .loaded {
            completion(true)
        } else {
            asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"], completionHandler: {
                var error: NSError?
                var error1: NSError?
                if asset.statusOfValue(forKey: "tracks", error: &error) == .loaded && asset.statusOfValue(forKey: "duration", error: &error1) == .loaded {
                    completion(true)
                } else {
                    if error != nil {
                        print("could not load asset's duation: \(error?.localizedDescription ?? "Unknown error")")
                    }
                    if error1 != nil {
                        print("could not load asset's tracks: \(error?.localizedDescription ?? "Unknown error")")
                    }
                    completion(false)
                }
            })
        }
    }
    
}

class SampleBufferProcessOperation {
    var sampleMax: CGFloat = 0
    let samplesPerPixel: Int
    let filter: [Float]
    
    var outputSamples = [CGFloat]()
    var sampleBuffer = Data()
    
    init(samplesPerPixel: Int) {
        self.samplesPerPixel = samplesPerPixel
        self.filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)
    }
    
    func appendSampleBuffer(_ readSampleBuffer: CMSampleBuffer) {
        guard let readBuffer = CMSampleBufferGetDataBuffer(readSampleBuffer) else { return }
        var readBufferLength = 0
        var readBufferPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(readBuffer, 0, &readBufferLength, nil, &readBufferPointer)
        sampleBuffer.append(UnsafeBufferPointer(start: readBufferPointer, count: readBufferLength))
        
        let totalSamples = sampleBuffer.count / MemoryLayout<Int16>.size
        let downSampledLength = totalSamples / samplesPerPixel
        let samplesToProcess = downSampledLength * samplesPerPixel
        
        guard samplesToProcess > 0 else { return }
        
        processSamples(fromData: &sampleBuffer,
                       sampleMax: &sampleMax,
                       outputSamples: &outputSamples,
                       samplesToProcess: samplesToProcess,
                       downSampledLength: downSampledLength,
                       samplesPerPixel: samplesPerPixel,
                       filter: filter)
    }
    
    func processRemaining() {
        let samplesToProcess = sampleBuffer.count / MemoryLayout<Int16>.size
        if samplesToProcess > 0 {
            let downSampledLength = 1
            let samplesPerPixel = samplesToProcess
            let filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)
            
            processSamples(fromData: &sampleBuffer,
                           sampleMax: &sampleMax,
                           outputSamples: &outputSamples,
                           samplesToProcess: samplesToProcess,
                           downSampledLength: downSampledLength,
                           samplesPerPixel: samplesPerPixel,
                           filter: filter)
        }
    }
    
    fileprivate func processSamples(fromData sampleBuffer: inout Data, sampleMax: inout CGFloat, outputSamples: inout [CGFloat], samplesToProcess: Int, downSampledLength: Int, samplesPerPixel: Int, filter: [Float]) {
        sampleBuffer.withUnsafeBytes { (samples: UnsafePointer<Int16>) in
            var processingBuffer = [Float](repeating: 0.0, count: samplesToProcess)
            
            let sampleCount = vDSP_Length(samplesToProcess)
            
            //Convert 16bit int samples to floats
            vDSP_vflt16(samples, 1, &processingBuffer, 1, sampleCount)
            
            //Take the absolute values to get amplitude
            vDSP_vabs(processingBuffer, 1, &processingBuffer, 1, sampleCount)
            
            //Downsample and average
            var downSampledData = [Float](repeating: 0.0, count: downSampledLength)
            vDSP_desamp(processingBuffer,
                        vDSP_Stride(samplesPerPixel),
                        filter, &downSampledData,
                        vDSP_Length(downSampledLength),
                        vDSP_Length(samplesPerPixel))
            
            let downSampledDataCG = downSampledData.map { (value: Float) -> CGFloat in
                let element = CGFloat(value)
                if element > sampleMax { sampleMax = element }
                return element
            }
            
            // Remove processed samples
            sampleBuffer.removeFirst(samplesToProcess * MemoryLayout<Int16>.size)
            
            outputSamples += downSampledDataCG
        }
    }
    
}

private class WaveformScrollView: UIScrollView {
    
    override class var layerClass: Swift.AnyClass {
        return CAShapeLayer.classForCoder()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    fileprivate func commonInit() {
        addObserver(self, forKeyPath: "contentOffset", options: .new, context: nil)
        let lay = layer as! CAShapeLayer
        lay.strokeColor = UIColor.black.cgColor
        lay.fillColor = UIColor.white.cgColor
    }
    
    deinit {
        removeObserver(self, forKeyPath: "contentOffset")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "contentOffset" {
            drawSamplesIfNeed()
        }
    }
    
    fileprivate func drawSamplesIfNeed() {
        if samples.count == 0 {
            return
        }
        let leftIndex = Int(max(0, (contentOffset.x - 50) / 3 * 4))
        let rightIndex = min(samples.count - 1, Int((contentOffset.x + bounds.width + 50) / 3 * 4))
        let path = UIBezierPath()
        path.lineWidth = 0.5
        for i in leftIndex...rightIndex {
            let h = samples[i] / sampleMax
            let centerX = 0.5 * 0.5 + CGFloat(i) * 0.5 + CGFloat(i / 4)
            let x = centerX - 0.25
            let y = (1 - h) * 100 * 0.5
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + h * 100))
        }
        let lay = layer as! CAShapeLayer
        lay.path = path.cgPath
    }
    
    fileprivate var samples: [CGFloat] = []
    fileprivate var sampleMax: CGFloat = 100
    fileprivate var index = 0
    func drawSamples(_ samples: [CGFloat]) {
        self.samples = samples
        drawSamplesIfNeed()
    }
    
}
