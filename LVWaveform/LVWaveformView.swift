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
    func waveformViewFrameDidCalc()
}

class LVWaveformView: UIView {
    
    weak var delegate: LVWaveformViewDelegate?
    var recommendWidth: CGFloat = 0
    var widthPerSec: CGFloat = 60 // 每一秒的宽度
    var samplePerSec: Int = 80
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    fileprivate weak var collectionView: UICollectionView!
    fileprivate func commonInit() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 1, height: 100)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = UIColor.clear
        collectionView.register(WaveformCollectionViewCell.classForCoder(), forCellWithReuseIdentifier: "WaveformCollectionViewCellIdentifier")
        addSubview(collectionView)
        self.collectionView = collectionView
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
    }
    
    fileprivate var samples: [WaveformModel] = []
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
        
        recommendWidth = floor(CGFloat(asset.duration.seconds) * widthPerSec)
        DispatchQueue.main.async {
            self.delegate?.waveformViewFrameDidCalc()
        }
        
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
        }
        
        // Process the remaining samples at the end which didn't fit into samplesPerPixel
        operation.processRemaining()
        
        if reader.status == .completed {
            DispatchQueue.main.async {
                self.reloadData(operation, width: self.recommendWidth)
            }
        } else {
            print("LVWaveformView failed to read audio: \(String(describing: reader.error))")
        }
    }
    
    func reloadData(_ operation: SampleBufferProcessOperation, width: CGFloat) {
        samples.removeAll()
        var index = 0
        var model = WaveformModel()
        for sample in operation.outputSamples {
            if index == samplePerSec {
                model.width = widthPerSec
                samples.append(model)
                model = WaveformModel()
                index = 0
            }
            model.data.append(sample / operation.sampleMax)
            index += 1
        }
        if index != samplePerSec {
            model.width = width - CGFloat(samples.count) * widthPerSec
            samples.append(model)
        }
        collectionView.reloadData()
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

extension LVWaveformView: UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return samples.count
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: samples[indexPath.item].width, height: 100)
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "WaveformCollectionViewCellIdentifier", for: indexPath) as! WaveformCollectionViewCell
        cell.setModel(samples[indexPath.item])
        return cell
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
        CMSampleBufferInvalidate(readSampleBuffer)
        
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

private class WaveformModel {
    var width: CGFloat = 0
    var data: [CGFloat] = []
}

private class WaveformCollectionViewCell: UICollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    fileprivate var lineLayers: [CALayer] = []
    fileprivate func commonInit() {
    }
    
    fileprivate var model: WaveformModel?
    func setModel(_ model: WaveformModel) {
        if model !== self.model {
            self.model = model
            for lineLayer in lineLayers {
                lineLayer.removeFromSuperlayer()
            }
            lineLayers.removeAll()
            var centerX: CGFloat = 0.5 * 0.5
            var index = 0
            for h in model.data {
                let layer = CALayer()
                layer.backgroundColor = UIColor.black.cgColor
                layer.bounds = CGRect(x: 0, y: 0, width: 0.5, height: h * 100)
                layer.position = CGPoint(x: centerX, y: 50)
                contentView.layer.addSublayer(layer)
                lineLayers.append(layer)
                centerX += 0.5
                if index % 4 == 3 {
                    centerX += 1
                }
                index += 1
            }
        }
    }
    
}
