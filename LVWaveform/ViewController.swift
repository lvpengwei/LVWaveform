//
//  ViewController.swift
//  LVWaveform
//
//  Created by lvpengwei on 9/28/17.
//  Copyright © 2017 lvpengwei. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

    @IBOutlet weak var waveformView: LVWaveformView!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        waveformView.delegate = self
        if let path = Bundle.main.path(forResource: "TchaikovskyExample2", ofType: "m4a") {
            let asset = AVAsset(url: URL(fileURLWithPath: path))
            waveformView.showAsset(asset)
        }
    }

}

extension ViewController: LVWaveformViewDelegate {
    func waveformViewFrameDidCalc() {
        print(waveformView.recommendWidth)
    }
    func waveformViewAssetLoadError() {
        
    }
}
