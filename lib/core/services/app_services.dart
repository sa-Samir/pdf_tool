import 'package:flutter/widgets.dart';

import '../engine/pdf_engine.dart';
import '../engine/pdf_manipulator_engine.dart';
import '../files/document_store.dart';
import '../files/export_service.dart';
import '../files/file_importer.dart';

/// The app's shared services, resolved once and handed down the tree.
///
/// A plain InheritedWidget rather than a DI package: picking one is a Phase 1
/// architecture decision and nothing here needs more than this yet.
class AppServices {
  AppServices._({
    required this.engine,
    required this.store,
    required this.importer,
    required this.export,
  });

  factory AppServices({
    PdfEngine? engine,
    DocumentStore? store,
    FileImporter? importer,
    ExportService export = const ExportService(),
  }) {
    final resolvedEngine = engine ?? PdfManipulatorEngine();
    final resolvedStore = store ?? DocumentStore(engine: resolvedEngine);
    return AppServices._(
      engine: resolvedEngine,
      store: resolvedStore,
      importer: importer ?? SystemFileImporter(store: resolvedStore),
      export: export,
    );
  }

  final PdfEngine engine;
  final DocumentStore store;
  final ExportService export;
  final FileImporter importer;

  Future<void> dispose() => engine.dispose();
}

class AppServicesScope extends InheritedWidget {
  const AppServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppServicesScope>();
    assert(scope != null, 'No AppServicesScope found above this widget.');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppServicesScope oldWidget) =>
      oldWidget.services != services;
}
