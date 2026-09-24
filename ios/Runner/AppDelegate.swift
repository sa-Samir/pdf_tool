import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the app's lifetime: the document picker's delegate must outlive
  /// the call that presents it.
  private var deviceExport: DeviceExportHandler?
  private var documentPrint: DocumentPrintHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(
      application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let handler = DeviceExportHandler(presenter: controller)
      deviceExport = handler
      FlutterMethodChannel(
        name: "com.samir.pdf_toolbox/device_export",
        binaryMessenger: controller.binaryMessenger
      ).setMethodCallHandler { call, result in
        handler.handle(call, result: result)
      }

      let printer = DocumentPrintHandler(presenter: controller)
      documentPrint = printer
      FlutterMethodChannel(
        name: "com.samir.pdf_toolbox/print",
        binaryMessenger: controller.binaryMessenger
      ).setMethodCallHandler { call, result in
        printer.handle(call, result: result)
      }
    }

    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
