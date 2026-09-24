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
