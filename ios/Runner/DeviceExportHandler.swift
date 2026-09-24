import Flutter
import UIKit

/// Copies finished documents out to the Files app (requirements.md 6).
///
/// `asCopy: true` is the whole contract: the system copies our file to the
/// place the user chose and leaves ours untouched, so the library still holds
/// the document afterwards. It also takes URLs rather than bytes, so a 200 MB
/// document costs no memory (requirements.md 13).
final class DeviceExportHandler: NSObject, UIDocumentPickerDelegate {

  private var pending: FlutterResult?
  private weak var presenter: UIViewController?

  init(presenter: UIViewController) {
    self.presenter = presenter
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "save" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let paths = arguments["paths"] as? [String],
      !paths.isEmpty
    else {
      result(Self.reply(status: "cancelled", count: 0))
      return
    }
    guard pending == nil else {
      result(FlutterError(
        code: "busy",
        message: "A save is already in progress.",
        details: nil))
      return
    }
    guard let presenter = presenter else {
      result(Self.reply(status: "failed", count: 0))
      return
    }

    pending = result
    let picker = UIDocumentPickerViewController(
      forExporting: paths.map { URL(fileURLWithPath: $0) },
      asCopy: true)
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    // Report what actually landed, not what was asked for.
    settle(Self.reply(
      status: urls.isEmpty ? "failed" : "saved",
      count: urls.count,
      location: urls.first?.deletingLastPathComponent().lastPathComponent))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    // Backing out of the picker is a choice, not a failure.
    settle(Self.reply(status: "cancelled", count: 0))
  }

  private func settle(_ outcome: [String: Any?]) {
    pending?(outcome)
    pending = nil
  }

  private static func reply(
    status: String,
    count: Int,
    location: String? = nil
  ) -> [String: Any?] {
    ["status": status, "count": count, "location": location]
  }
}

/// Hands a PDF to the system print UI (requirements.md 6).
///
/// `printingItem` takes a file URL, so the document is never loaded into
/// memory -- the same reason the exporter avoids byte-based APIs
/// (requirements.md 13).
final class DocumentPrintHandler: NSObject {

  private weak var presenter: UIViewController?

  init(presenter: UIViewController) {
    self.presenter = presenter
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "print" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard UIPrintInteractionController.isPrintingAvailable else {
      result(["status": "unsupported"])
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String
    else {
      result(["status": "failed"])
      return
    }

    let url = URL(fileURLWithPath: path)
    guard UIPrintInteractionController.canPrint(url) else {
      result(["status": "failed"])
      return
    }

    let info = UIPrintInfo.printInfo()
    info.outputType = .general
    info.jobName = (arguments["jobName"] as? String) ?? url.lastPathComponent

    let controller = UIPrintInteractionController.shared
    controller.printInfo = info
    controller.printingItem = url

    // On iPad the print sheet is a popover and needs somewhere to come from,
    // or it simply does not appear.
    if UIDevice.current.userInterfaceIdiom == .pad, let view = presenter?.view {
      let anchor = CGRect(x: view.bounds.midX, y: view.bounds.midY,
                          width: 0, height: 0)
      controller.present(from: anchor, in: view, animated: true) { _, _, _ in }
    } else {
      controller.present(animated: true) { _, _, _ in }
    }

    // Reported once the system UI has the document. Whether the user prints
    // it, saves it as a PDF or backs out is between them and that UI.
    result(["status": "started"])
  }
}
