//
//  MainViewController.swift
//  Stereoscope
//
//  Created by Louis Franco on 6/25/17.
//  Copyright © 2017 Lou Franco. All rights reserved.
//

import UIKit

class MainViewController: UIViewController, CameraDelegate {

    // Normal View
    @IBOutlet var imageView: UIImageView! = nil

    @IBOutlet var leftCaptureButton: UIButton! = nil
    @IBOutlet var rightCaptureButton: UIButton! = nil

    @IBOutlet var shareButton: UIButton! = nil
    @IBOutlet var clearButton: UIButton! = nil

    @IBOutlet var infoButton: UIButton! = nil

    // Empty/Error View
    @IBOutlet var emptyView: UIView! = nil
    @IBOutlet var errorView: UIView! = nil
    @IBOutlet var errorLabel: UILabel! = nil

    // Button State
    static let leftIsRedKey = "leftIsRedKey"
    var leftIsRed: Bool = false

    // Camera
    private var camera = Camera()

    // State
    var capturedDeviceSize: CGSize? = nil

    override var prefersStatusBarHidden: Bool {
        get { return true }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        subscribeToAppEvents()
        self.camera.delegate = self

        // Error View Style
        self.errorView.layer.borderColor = UIColor.gray.cgColor
        self.errorView.layer.borderWidth = 2
        self.errorView.isHidden = true

        // Button State
        self.setLeftIsRed(leftIsRed: UserDefaults.standard.bool(forKey: MainViewController.leftIsRedKey))
    }

    private func setLeftIsRed(leftIsRed: Bool) {
        self.leftIsRed = leftIsRed
        if leftIsRed {
            self.leftCaptureButton.setImage(UIImage(named: "camera-red"), for: .normal)
            self.rightCaptureButton.setImage(UIImage(named: "camera-blue"), for: .normal)
        } else {
            self.leftCaptureButton.setImage(UIImage(named: "camera-blue"), for: .normal)
            self.rightCaptureButton.setImage(UIImage(named: "camera-red"), for: .normal)
        }
        camera.setLeftIsRed(leftIsRed: leftIsRed)
        UserDefaults.standard.set(leftIsRed, forKey: MainViewController.leftIsRedKey)
    }

    // Camera Delegate
    func cameraDidStart() {
        DispatchQueue.main.async {
            self.hideEmptyView()
        }
    }

    func cameraDidError(with error: String) {
        DispatchQueue.main.async {
            self.showError(error: error)
        }
    }

    func makeCropRect(aspectRatio: CGSize, for size: CGSize) -> CGRect {
        let aspectRatioFraction = aspectRatio.width / aspectRatio.height
        let sizeFraction = size.width / size.height
        let r: CGRect
        if (aspectRatioFraction < sizeFraction) {
            let w = size.height * aspectRatioFraction
            r = CGRect(x: (size.width - w)/2, y: 0, width: w, height: size.height)
        } else {
            let h = size.width / aspectRatioFraction
            r = CGRect(x: 0, y: (size.height - h)/2, width: size.width, height: h)
        }
        return r
    }

    func sizeToDeviceRatio(image: UIImage) -> UIImage? {
        let r = makeCropRect(aspectRatio: self.capturedDeviceSize ?? self.imageView.bounds.size, for: image.size)
        if let croppedCgImage = image.cgImage?.cropping(to: r) {
            return UIImage(cgImage: croppedCgImage)
        }
        return nil
    }

    func show(image: UIImage) {
        DispatchQueue.main.async { [weak self] in
            self?.imageView?.image = self?.sizeToDeviceRatio(image: image)
        }
    }

    func bothSidesCaptured() {
        DispatchQueue.main.async { [weak self] in
            self?.capturedDeviceSize = self?.imageView.bounds.size
        }
    }

    // App Events
    private func subscribeToAppEvents() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    @objc private func appBecameActive() {
        self.camera.start()
    }

    @objc private func appResignActive() {
        self.camera.stop()
    }

    // Empty / Error View
    private func hideEmptyView() {
        UIView.animate(withDuration: 0.5) {
            self.errorView.isHidden = true
            self.emptyView.alpha = 0.0
        }
    }

    private func showError(error: String) {
        self.errorView.isHidden = false
        self.errorLabel.text = error
        UIView.animate(withDuration: 0.5) {
            self.emptyView.alpha = 1.0
        }
    }

    // Button events

    @IBAction func takeLeftPhoto(sender: UIButton) {
        camera.captureLeft()
    }

    @IBAction func takeRightPhoto(sender: UIButton) {
        camera.captureRight()
    }

    @IBAction func clearPhotos(sender: UIButton) {
        self.capturedDeviceSize = nil
        camera.clearCapturedPhotos()
    }

    @IBAction func sharePhoto(sender: UIButton) {
        if let image = self.imageView.image {
            let imageToShare = [ image ]
            let activityViewController = UIActivityViewController(activityItems: imageToShare, applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceRect = self.shareButton.bounds
            activityViewController.popoverPresentationController?.sourceView = self.shareButton
            self.present(activityViewController, animated: true, completion: nil)
        }
    }

    private func openURL(urlString: String) {
        if let url = URL(string: urlString) {
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                UIApplication.shared.openURL(url)
            }
        }
    }

    func urlAction(title: String, urlString: String) -> UIAlertAction {
        return UIAlertAction(title: title, style: .default) { [weak self] a in
            self?.openURL(urlString: urlString)
        }
    }

    @IBAction func info(sender: UIButton) {
        let infoMenu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        infoMenu.addAction(UIAlertAction(title: "Switch to \(self.leftIsRed ? "Cyan/Red":"Red/Cyan")", style: .default) { [weak self] a in
            self?.setLeftIsRed(leftIsRed: !(self?.leftIsRed ?? false))
        })
        infoMenu.addAction(urlAction(title: "Buy 3D Glasses", urlString: "http://amzn.to/2tBsFCQ"))
        infoMenu.addAction(urlAction(title: "Rate on the App Store", urlString: "https://itunes.apple.com/us/app/3d-o-mat/id1254858311?ls=1&mt=8&action=write-review"))
        infoMenu.addAction(urlAction(title: "Get Support", urlString: "http://loufranco.com/apps/3d-o-mat"))

        infoMenu.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        infoMenu.popoverPresentationController?.sourceRect = self.infoButton.bounds
        infoMenu.popoverPresentationController?.sourceView = self.infoButton

        self.present(infoMenu, animated: true, completion: nil)
    }
}

