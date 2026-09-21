/// The failure taxonomy from requirements.md 12.
///
/// Every failure in the app maps to exactly one of these. The mapping owns the
/// user-facing message, so no feature invents its own wording, and no raw
/// engine text ever reaches the screen.
enum FailureKind {
  corruptFile,
  passwordRequired,
  wrongPassword,
  permissionDenied,
  outOfStorage,
  tooLarge,
  pageOutOfRange,
  unsupported,
  cancelled,
  noResult,
  io,
  unknown,
}

class PdfFailure implements Exception {
  const PdfFailure(this.kind, {this.cause, this.detail});

  final FailureKind kind;
  final Object? cause;

  /// Extra context for the message, e.g. a page number. Never raw engine text.
  final String? detail;

  /// Requirements.md 12: no failure class consumes a free-tier use. Encoded
  /// here rather than left to each caller to remember.
  bool get consumesUse => false;

  /// Requirements.md 12: cancellation is silent.
  bool get isSilent => kind == FailureKind.cancelled;

  /// Whether this is worth a log line. Passwords never are.
  bool get isLoggable => switch (kind) {
        FailureKind.passwordRequired ||
        FailureKind.wrongPassword ||
        FailureKind.cancelled =>
          false,
        _ => true,
      };

  String get message => switch (kind) {
        FailureKind.corruptFile => "We can't open this PDF. It may be damaged.",
        FailureKind.passwordRequired => 'This PDF is password-protected.',
        FailureKind.wrongPassword => "That password didn't work.",
        FailureKind.permissionDenied =>
          "This PDF's owner has blocked changes to it.",
        FailureKind.outOfStorage =>
          'Not enough space on this device. Free some up and try again.',
        FailureKind.tooLarge =>
          'This document is too large to process on this device.',
        FailureKind.pageOutOfRange =>
          detail ?? 'That page does not exist in this document.',
        FailureKind.unsupported =>
          "This PDF uses something we can't handle yet.",
        FailureKind.cancelled => 'Cancelled.',
        FailureKind.noResult =>
          "Already optimized — we couldn't make this smaller.",
        FailureKind.io => "We couldn't read or write the file.",
        FailureKind.unknown =>
          'Something went wrong. Your original file was not changed.',
      };

  /// What the user can do next, where there is something.
  String? get recovery => switch (kind) {
        FailureKind.corruptFile => 'Try another file.',
        FailureKind.passwordRequired => 'Enter the password to continue.',
        FailureKind.wrongPassword => 'Check the password and try again.',
        FailureKind.outOfStorage => 'Free up space, then try again.',
        FailureKind.tooLarge => 'Try splitting the document first.',
        FailureKind.permissionDenied => 'Use the Unlock tool first.',
        _ => null,
      };

  @override
  String toString() => 'PdfFailure(${kind.name}${detail == null ? '' : ': $detail'})';
}
