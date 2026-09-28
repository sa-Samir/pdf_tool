import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What came of a scan (requirements.md 3.10).
enum ScanOutcome {
  captured,

  /// The user backed out of the camera. Not an error, and never reported as one.
  cancelled,

  /// Scanning cannot work on this device at all -- typically an Android build
  /// without Google Play services.
  unavailable,

  failed,
}

/// One captured page.
///
/// The size comes back from the platform rather than being measured here: the
/// review screen shows it, and reading it in Dart would put file I/O in the
/// widget layer, where a widget test's fake-async zone never completes it.
@immutable
class ScannedPage {
  const ScannedPage({required this.file, required this.sizeBytes});

  final File file;
  final int sizeBytes;
}

@immutable
class ScanResult {
  const ScanResult(this.outcome, {this.pages = const <ScannedPage>[]});

  const ScanResult.cancelled() : this(ScanOutcome.cancelled);

  final ScanOutcome outcome;

  /// One image per captured page, in the order the user arranged them.
  /// Written into a directory this app owns, so they can be handed straight to
  /// the PDF pipeline.
  final List<ScannedPage> pages;

  bool get hasPages => outcome == ScanOutcome.captured && pages.isNotEmpty;
}

/// Captures paper through the platform document scanners
/// (requirements.md 3.10).
///
/// VisionKit on iOS, ML Kit Document Scanner on Android. Both give edge
/// detection, perspective correction, retake and reorder for free, and both
/// are far better than anything worth building here.
abstract interface class DocumentScanner {
  /// Whether scanning can work on this device **at all**.
  ///
  /// Asked before the tool is offered, never at capture time. The Android
  /// scanner needs Google Play services and is simply absent on devices
  /// without them; a tool that fails only once the user has committed to it is
  /// worse than one that was never there (requirements.md 3.10).
  Future<bool> isAvailable();

  /// Opens the platform scanner. [pageLimit] caps capture where the platform
  /// supports it.
  ///
  /// The platform side chooses where pages land -- its own cache directory,
  /// cleared at the start of every capture -- and returns absolute paths.
  /// Deliberately not a directory this side picks: resolving one means file
  /// I/O, and file I/O on the path between a tap and the camera cannot
  /// complete inside a widget test's fake-async zone. The pages are read once,
  /// normalised into an operation's workspace, and never needed again.
  Future<ScanResult> scan({int? pageLimit});
}

class PlatformDocumentScanner implements DocumentScanner {
  const PlatformDocumentScanner();

  static const _channel = MethodChannel('com.samir.pdf_toolbox/scan');

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<ScanResult> scan({int? pageLimit}) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const ScanResult(ScanOutcome.unavailable);
    }
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('scan', {
        'pageLimit': pageLimit,
      });
      if (reply == null) return const ScanResult(ScanOutcome.failed);

      final outcome = switch (reply['status'] as String?) {
        'captured' => ScanOutcome.captured,
        'cancelled' => ScanOutcome.cancelled,
        'unavailable' => ScanOutcome.unavailable,
        _ => ScanOutcome.failed,
      };
      final raw = (reply['pages'] as List?) ?? const [];
      return ScanResult(
        outcome,
        pages: [
          for (final entry in raw.cast<Map<Object?, Object?>>())
            ScannedPage(
              file: File(entry['path']! as String),
              sizeBytes: (entry['bytes'] as int?) ?? 0,
            ),
        ],
      );
    } on PlatformException {
      return const ScanResult(ScanOutcome.failed);
    } on MissingPluginException {
      return const ScanResult(ScanOutcome.unavailable);
    }
  }
}
