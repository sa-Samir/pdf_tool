import 'package:flutter/material.dart';

import 'app/app.dart';

void main() {
  // No pre-runApp work: the native launch screen hands straight over to the
  // first Flutter frame, and the home screen renders before any file-system or
  // database work (requirements.md 3.0, 3.1).
  runApp(const PdfToolboxApp());
}
