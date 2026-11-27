import Flutter
import UIKit
import AVFoundation
import RoomPlan
import simd

public final class RoomScanPlugin: NSObject, FlutterPlugin {
    private var pending: FlutterResult?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.showroomxr/room_scan", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(RoomScanPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(call.method == "isSupported" ? false : FlutterError(code: "unsupported", message: "RoomPlan needs iOS 16.", details: nil))
            return
        }
        if call.method == "isSupported" { result(RoomCaptureSession.isSupported); return }
        guard call.method == "scan" else { result(FlutterMethodNotImplemented); return }
        guard RoomCaptureSession.isSupported else {
            result(FlutterError(code: "unsupported", message: "LiDAR is required.", details: nil)); return
        }
        guard pending == nil else {
            result(FlutterError(code: "busy", message: "A scan is already active.", details: nil)); return
        }
        pending = result
        let arabic = (call.arguments as? [String: Any])?["arabic"] as? Bool ?? false
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard granted else {
                    self.complete(FlutterError(code: "camera_denied", message: "Camera permission is required.", details: nil)); return
                }
                let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
                guard var presenter = windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                    self.complete(FlutterError(code: "no_presenter", message: "Unable to show the scanner.", details: nil)); return
                }
                while let next = presenter.presentedViewController { presenter = next }
                let scanner = RoomScannerController(arabic: arabic) { [weak self] value in self?.complete(value) }
                let navigation = UINavigationController(rootViewController: scanner)
                navigation.modalPresentationStyle = .fullScreen
                presenter.present(navigation, animated: true)
            }
        }
    }

    private func complete(_ value: Any?) {
        let callback = pending
        pending = nil
        callback?(value)
    }
}

@available(iOS 16.0, *)
private final class RoomScannerController: UIViewController, RoomCaptureViewDelegate {
    private let capture = RoomCaptureView(frame: .zero)
    private let arabic: Bool
    private let completion: (Any?) -> Void
    private var started = false
    private var finished = false
    private var processing = false

    init(arabic: Bool, completion: @escaping (Any?) -> Void) {
        self.arabic = arabic
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = arabic ? "مسح الغرفة" : "Scan your room"
        capture.delegate = self
        capture.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(capture)
        NSLayoutConstraint.activate([
            capture.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            capture.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            capture.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            capture.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: arabic ? "إلغاء" : "Cancel", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: arabic ? "تم" : "Done", style: .done, target: self, action: #selector(done))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !started { started = true; capture.captureSession.run(configuration: .init()) }
    }

    @objc private func done() {
        guard !processing else { return }
        processing = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        capture.captureSession.stop()
    }

    @objc private func cancel() {
        guard !finished else { return }
        finished = true
        capture.captureSession.stop()
        dismiss(animated: true) { self.completion(FlutterError(code: "cancelled", message: nil, details: nil)) }
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if finished { return false }
        if let error = error {
            finish(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil))
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        guard !finished else { return }
        if let error = error {
            finish(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil)); return
        }
        do {
            let encoded = try JSONEncoder().encode(processedResult)
            var output: [String: Any] = [
                "wallCount": processedResult.walls.count,
                "doorCount": processedResult.doors.count,
                "windowCount": processedResult.windows.count,
                "objectCount": processedResult.objects.count,
                "scanJson": String(decoding: encoded, as: UTF8.self),
                "rectangular": false
            ]
            if let estimate = estimateRectangle(processedResult) {
                output["rectangular"] = estimate.valid
                output["dimensions"] = ["width": estimate.width, "depth": estimate.depth, "height": estimate.height]
            }
            // The scan remains a parametric room. It is never substituted for a catalogue furniture model.
            finish(output)
        } catch {
            finish(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil))
        }
    }

    private func finish(_ value: Any?) {
        guard !finished else { return }
        finished = true
        capture.captureSession.stop()
        dismiss(animated: true) { self.completion(value) }
    }

    /// Draft dimensions only. Reject an irregular outline instead of inventing a rectangle.
    private func estimateRectangle(_ room: CapturedRoom) -> (valid: Bool, width: Float, depth: Float, height: Float)? {
        guard let base = room.walls.max(by: { $0.dimensions.x < $1.dimensions.x }), room.walls.count >= 4 else { return nil }
        let axis = SIMD3<Float>(base.transform.columns.0.x, 0, base.transform.columns.0.z)
        guard simd_length(axis) > 0.01 else { return nil }
        let u = simd_normalize(axis), v = SIMD3<Float>(-u.z, 0, u.x)
        var points: [SIMD2<Float>] = []
        var directions: [SIMD2<Float>] = []
        for wall in room.walls {
            let c = SIMD3<Float>(wall.transform.columns.3.x, 0, wall.transform.columns.3.z)
            let x = SIMD3<Float>(wall.transform.columns.0.x, 0, wall.transform.columns.0.z)
            guard simd_length(x) > 0.01 else { return nil }
            let along = simd_normalize(x)
            directions.append(SIMD2<Float>(simd_dot(along, u), simd_dot(along, v)))
            for sign in [Float(-1), Float(1)] {
                let p = c + along * wall.dimensions.x / 2 * sign
                points.append(SIMD2<Float>(simd_dot(p, u), simd_dot(p, v)))
            }
        }
        guard let minX = points.map({$0.x}).min(), let maxX = points.map({$0.x}).max(),
              let minZ = points.map({$0.y}).min(), let maxZ = points.map({$0.y}).max() else { return nil }
        let width = maxX-minX, depth = maxZ-minZ
        let heights = room.walls.map { $0.dimensions.y }.sorted()
        let height = heights[heights.count/2]
        var sides = Set<Int>()
        var valid = room.walls.count == 4 && width >= 1 && depth >= 1 && width <= 25 && depth <= 25 &&
            height >= 2 && height <= 10
        for i in room.walls.indices {
            let a = points[i*2], b = points[i*2+1], direction = directions[i]
            let horizontal = abs(direction.x) > 0.996
            let vertical = abs(direction.y) > 0.996
            let side: Int
            if horizontal && abs(a.y-minZ) < 0.10 && abs(b.y-minZ) < 0.10 { side = 0 }
            else if horizontal && abs(a.y-maxZ) < 0.10 && abs(b.y-maxZ) < 0.10 { side = 1 }
            else if vertical && abs(a.x-minX) < 0.10 && abs(b.x-minX) < 0.10 { side = 2 }
            else if vertical && abs(a.x-maxX) < 0.10 && abs(b.x-maxX) < 0.10 { side = 3 }
            else { valid = false; continue }
            if !sides.insert(side).inserted { valid = false }
            let fullSpan = horizontal ? width : depth
            if abs(simd_distance(a,b) - fullSpan) > 0.15 { valid = false }
            if case .low = room.walls[i].confidence { valid = false }
        }
        return (valid && sides.count == 4, width, depth, height)
    }
}
