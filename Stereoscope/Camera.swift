//
//  Camera.swift
//  Stereoscope
//
//  Created by Louis Franco on 7/1/17.
//  Copyright © 2017 Lou Franco. All rights reserved.
//

import Foundation
import AVFoundation
import CoreImage
import UIKit


protocol CameraDelegate: class {
    func cameraDidStart()
    func show(image: UIImage)
    func cameraDidError(with error: String)
}

class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    public weak var delegate: CameraDelegate? = nil

    private var captureSession: AVCaptureSession?

    private let cameraPosition = AVCaptureDevicePosition.back
    private let context = CIContext()

    private var hasCameraPermission: Bool = false
    private var cameraConfigured = false

    private let sessionQueue = DispatchQueue(label: "AVCapture sessionQueue")

    private var shouldCaptureLeft = false
    private var shouldCaptureRight = false

    private var leftPhoto: CIImage? = nil
    private var rightPhoto: CIImage? = nil

    private var leftIsRed = false


    public func start() {
        getCameraPermission()
        sessionQueue.async { [weak self] in
            if (self?.hasCameraPermission ?? false) {
                if (self?.configureSession() ?? false) {
                    self?.cameraConfigured = true
                    self?.captureSession?.startRunning()
                    self?.delegate?.cameraDidStart()
                } else {
                    self?.delegate?.cameraDidError(with: "This device's camera could not be found.")
                }
            } else {
                self?.delegate?.cameraDidError(with: "3D-o-Mat needs permission to use the camera.\nTurn on camera permission in the Settings App.")
            }
        }
    }

    public func stop() {
        self.captureSession?.stopRunning()
    }

    public func captureLeft() {
        shouldCaptureLeft = true
    }

    public func captureRight() {
        shouldCaptureRight = true
    }

    public func clearCapturedPhotos() {
        self.leftPhoto = nil
        self.rightPhoto = nil
    }

    public func setLeftIsRed(leftIsRed: Bool) {
        self.leftIsRed = leftIsRed
    }

    private func getCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case .authorized:
            self.hasCameraPermission = true
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) { [weak self] granted in
                self?.hasCameraPermission = granted
                self?.sessionQueue.resume()
            }
        case .denied, .restricted:
            break
        }
    }

    private func configure(input: AVCaptureDeviceInput) -> Bool {
        self.captureSession = AVCaptureSession()
        let sessionOutput = AVCaptureVideoDataOutput()
        if let captureSession = captureSession, captureSession.canAddInput(input) {
            captureSession.addInput(input)
            sessionOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)

            if (captureSession.canAddOutput(sessionOutput)){
                captureSession.addOutput(sessionOutput)
                guard let connection = sessionOutput.connection(withMediaType: AVMediaTypeVideo) else { return false }
                guard connection.isVideoOrientationSupported else { return false }
                guard connection.isVideoMirroringSupported else { return false }
                connection.videoOrientation = .landscapeRight
                connection.isVideoMirrored = (self.cameraPosition == .front)
            }
            return true
        }
        return false
    }

    @available(iOS 10.0, *)
    private func configureSession10() -> Bool {
        let deviceTypes: [AVCaptureDeviceType] = [ .builtInTelephotoCamera, .builtInWideAngleCamera]

        guard let deviceDiscoverySession = AVCaptureDeviceDiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaTypeVideo, position: self.cameraPosition) else { return false }
        for device in (deviceDiscoverySession.devices) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if configure(input: input) {
                    return true
                }
            }
            catch {

            }
        }
        return false
    }

    private func configureSession9() -> Bool {
        do {
            let device = AVCaptureDevice.devices().filter {
                ($0 as AnyObject).hasMediaType(AVMediaTypeVideo) &&
                    ($0 as AnyObject).position == cameraPosition
                }.first as? AVCaptureDevice

            let input = try AVCaptureDeviceInput(device: device)
            return configure(input: input)
        } catch {

        }
        return false
    }

    private func configureSession() -> Bool {
        if #available(iOS 10.0, *) {
            return configureSession10()
        } else {
            return configureSession9()
        }
    }

    private func set(images: (left: CIImage, right: CIImage), on filter: CIFilter) {
        // Put the appropriate image in the red channel, and put the other one 
        // in both the green and blue (for cyan)
        if (self.leftIsRed) {
            filter.setValue(images.left, forKey: "inputChannelRed")
            filter.setValue(images.right, forKey: "inputChannelGreen")
            filter.setValue(images.right, forKey: "inputChannelBlue")
        } else {
            filter.setValue(images.right, forKey: "inputChannelRed")
            filter.setValue(images.left, forKey: "inputChannelGreen")
            filter.setValue(images.left, forKey: "inputChannelBlue")
        }
    }

    private func create3DPhoto(imageBuffer: CVImageBuffer) -> UIImage? {
        let imageCaptured = CIImage(cvPixelBuffer: imageBuffer)

        if self.shouldCaptureLeft {
            self.leftPhoto = imageCaptured
            self.shouldCaptureLeft = false
        }

        if self.shouldCaptureRight {
            self.rightPhoto = imageCaptured
            self.shouldCaptureRight = false
        }

        // If there is a taken left photo, use it, otherwise, use the captured buffer
        let imageLeft = self.leftPhoto ?? imageCaptured

        // If there is a taken right photo, use it, otherwise, use the captured buffer
        let imageRight = self.rightPhoto ?? imageCaptured

        guard let combineChannelsFilter = CIFilter(name: "CombineChannelsFilter") else { return nil }
        set(images: (left: imageLeft, right: imageRight), on: combineChannelsFilter)

        // return the image
        guard let combineChannelsImage = combineChannelsFilter.outputImage else { return nil }
        guard let cgImage = self.context.createCGImage(combineChannelsImage, from: combineChannelsImage.extent)
            else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate


    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        switch UIDevice.current.orientation {
        case .landscapeRight:
            connection.videoOrientation = .landscapeLeft
        case .landscapeLeft:
            connection.videoOrientation = .landscapeRight
        case .portrait:
            connection.videoOrientation = .portrait
        default:
            break
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Draw the image on the screen
        guard let uiImage = create3DPhoto(imageBuffer: imageBuffer) else { return }
        self.delegate?.show(image: uiImage)
    }


}
