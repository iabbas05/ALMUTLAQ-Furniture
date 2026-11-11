import ARKit
import Flutter
import QuickLook
import UIKit

/// Presents the bundled product at true scale. No remote AR host is required.
final class ProductARPlugin: NSObject, FlutterPlugin, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private let registrar: FlutterPluginRegistrar
    private var item: ARQuickLookPreviewItem?
    private var active = false

    init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "almutlaq/product_ar", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(ProductARPlugin(registrar: registrar), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "preview" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any],
              let sku = args["sku"] as? String, ["10_14_3", "6_14_5"].contains(sku) else {
            result(FlutterError(code: "unsupported_product", message: "No approved preview for this product", details: nil)); return
        }
        guard !active else {
            result(FlutterError(code: "busy", message: "Close the current preview first", details: nil)); return
        }
        let key = registrar.lookupKey(forAsset: "assets/london-\(sku).usdz")
        guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
            result(FlutterError(code: "missing_model", message: "Bundled model missing", details: nil)); return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var presenter = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
            result(FlutterError(code: "no_presenter", message: "No active screen", details: nil)); return
        }
        while let shown = presenter.presentedViewController { presenter = shown }
        let previewItem = ARQuickLookPreviewItem(fileAt: URL(fileURLWithPath: path))
        previewItem.allowsContentScaling = false
        item = previewItem
        let controller = QLPreviewController()
        controller.dataSource = self
        controller.delegate = self
        active = true
        presenter.present(controller, animated: true) {
            result(["opened": true, "arSupported": ARWorldTrackingConfiguration.isSupported])
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { item == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { item! }
    func previewControllerDidDismiss(_ controller: QLPreviewController) { active = false; item = nil }
}
