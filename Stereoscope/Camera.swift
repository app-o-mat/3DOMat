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
    func bothSidesCaptured()
}

class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    public weak var delegate: CameraDelegate? = nil

    private var captureSession: AVCaptureSession?

    private let cameraPosition = AVCaptureDevice.Position.back
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
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            self.hasCameraPermission = true
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: AVMediaType.video) { [weak self] granted in
                self?.hasCameraPermission = granted
                self?.sessionQueue.resume()
            }
        case .denied, .restricted:
            break
        @unknown default:
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
                guard let connection = sessionOutput.connection(with: AVMediaType.video) else { return false }
                guard connection.isVideoOrientationSupported else { return false }
                guard connection.isVideoMirroringSupported else { return false }
                connection.videoOrientation = .landscapeRight
                connection.isVideoMirrored = (self.cameraPosition == .front)
            }
            return true
        }
        return false
    }

    private func configureSession() -> Bool {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [ .builtInTelephotoCamera, .builtInWideAngleCamera]

        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaType.video, position: self.cameraPosition)
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

            if let _ = self.rightPhoto {
                self.delegate?.bothSidesCaptured()
            }
        }

        if self.shouldCaptureRight {
            self.rightPhoto = imageCaptured
            self.shouldCaptureRight = false

            if let _ = self.leftPhoto {
                self.delegate?.bothSidesCaptured()
            }
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



    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
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
