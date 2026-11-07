import AVFoundation
import SwiftUI
import UIKit

/// Full-screen camera for close-up pill photos.
///
/// Uses the back "virtual" multi-camera device (triple or dual-wide) when available. With automatic
/// lens switching, iOS moves to the ultra-wide lens for macro focus as the phone gets close to the
/// subject, the same as the built-in Camera app. Phones without an ultra-wide camera fall back to the
/// normal wide lens. Photos are cropped to the square shown in the viewfinder.
struct MacroCameraView: View {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var camera = MacroCameraModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = camera.captured {
                review(image)
            } else {
                live
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .statusBarHidden()
    }

    // MARK: - Live viewfinder

    private var live: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if camera.hasTorch {
                    Button { camera.toggleTorch() } label: {
                        Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel(camera.torchOn ? "Turn light off" : "Turn light on")
                }
            }
            .foregroundStyle(.white)
            .padding()

            Spacer(minLength: 0)

            ZStack {
                switch camera.state {
                case .starting, .ready:
                    CameraPreview(session: camera.session) { camera.focus(at: $0) }
                    Circle()
                        .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .padding(56)
                        .allowsHitTesting(false)
                case .denied:
                    VStack(spacing: 12) {
                        Text("Camera access is turned off for Med Supply.")
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .foregroundStyle(.white)
                    .padding()
                case .unavailable:
                    Text("No camera is available on this device.").foregroundStyle(.white)
                case .failed(let message):
                    Text(message).foregroundStyle(.white).padding()
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()

            Text("Get close to the pill and tap it to focus.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .padding()

            Spacer(minLength: 0)

            Button { camera.capture() } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 64, height: 64)
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                }
            }
            .disabled(!camera.isReady || camera.isCapturing)
            .opacity(camera.isReady ? 1 : 0.4)
            .accessibilityLabel("Take photo")
            .padding(.bottom, 32)
        }
    }

    // MARK: - Review

    private func review(_ image: UIImage) -> some View {
        VStack {
            Spacer()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
            Spacer()
            HStack {
                Button("Retake") { camera.retake() }
                Spacer()
                Button("Use Photo") {
                    onCapture(image)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            .font(.title3)
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Camera model

final class MacroCameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum State {
        case starting, ready, denied, unavailable
        case failed(String)
    }

    @Published var state: State = .starting
    @Published var captured: UIImage?
    @Published var isCapturing = false
    @Published var hasTorch = false
    @Published var torchOn = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "MedSupply.camera")
    private var device: AVCaptureDevice?
    private var configured = false

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.queue.async { self.configureAndRun() }
                } else {
                    self.publish { $0.state = .denied }
                }
            }
        default:
            state = .denied
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func retake() {
        captured = nil
        queue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func capture() {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        queue.async {
            if let connection = self.output.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90 // portrait
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    /// `devicePoint` is in the capture device's coordinate space (0...1).
    func focus(at devicePoint: CGPoint) {
        queue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    func toggleTorch() {
        queue.async {
            guard let device = self.device, device.hasTorch,
                  (try? device.lockForConfiguration()) != nil else { return }
            let on = device.torchMode != .on
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            self.publish { $0.torchOn = on }
        }
    }

    // MARK: Setup (runs on `queue`)

    private func configureAndRun() {
        if !configured {
            guard let device = Self.bestBackCamera() else {
                publish { $0.state = .unavailable }
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .photo
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    publish { $0.state = .failed("The camera couldn't be started.") }
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                output.maxPhotoQualityPrioritization = .quality
            } catch {
                session.commitConfiguration()
                publish { $0.state = .failed("The camera couldn't be started: \(error.localizedDescription)") }
                return
            }
            session.commitConfiguration()
            configureLens(device)
            self.device = device
            configured = true
            let torch = device.hasTorch
            publish { $0.hasTorch = torch }
        }
        if !session.isRunning { session.startRunning() }
        publish { $0.state = .ready }
    }

    /// Prefer multi-camera devices: they can switch to the ultra-wide lens for macro close-ups.
    private static func bestBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
        }
        return nil
    }

    private func configureLens(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if device.isVirtualDevice {
            // Let iOS pick the lens, including the ultra-wide for close focus (macro).
            device.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
            // Start framed like the standard 1x lens instead of the ultra-wide's 0.5x view.
            if let oneX = device.virtualDeviceSwitchOverVideoZoomFactors.first {
                device.videoZoomFactor = CGFloat(truncating: oneX)
            }
        }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
    }

    private func publish(_ change: @escaping (MacroCameraModel) -> Void) {
        DispatchQueue.main.async { change(self) }
    }

    // MARK: AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image = photo.fileDataRepresentation()
            .flatMap { UIImage(data: $0) }
            .map { Self.centerSquare($0, side: 1024) }
        if image != nil { queue.async { self.session.stopRunning() } }
        publish { model in
            model.isCapturing = false
            model.torchOn = false
            if let image { model.captured = image }
        }
    }

    /// Crops to the centered square (what the viewfinder shows) and scales to `side` pixels.
    static func centerSquare(_ image: UIImage, side: CGFloat) -> UIImage {
        let size = image.size // already accounts for orientation
        let crop = min(size.width, size.height)
        let scale = side / crop
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (crop - size.width) / 2 * scale,
                                  y: (crop - size.height) / 2 * scale,
                                  width: size.width * scale,
                                  height: size.height * scale))
        }
    }
}

// MARK: - Preview layer

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onTapFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTapFocus = onTapFocus
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onTapFocus: ((CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            let point = previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self))
            onTapFocus?(point)
        }
    }
}
