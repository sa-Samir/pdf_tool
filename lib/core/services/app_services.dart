import 'package:flutter/widgets.dart';

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../engine/pdf_engine.dart';
import '../engine/pdf_manipulator_engine.dart';
import '../files/document_store.dart';
import '../files/export_service.dart';
import '../files/file_importer.dart';
import '../library/library_repository.dart';
import '../library/sqflite_library_repository.dart';
import 'package:sqflite/sqflite.dart' show Database;

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
    required this.library,
  });

  factory AppServices({
    PdfEngine? engine,
    DocumentStore? store,
    FileImporter? importer,
    LibraryRepository? library,
    ExportService export = const ExportService(),
  }) {
    final resolvedEngine = engine ?? PdfManipulatorEngine();
    final resolvedStore = store ?? DocumentStore(engine: resolvedEngine);
    return AppServices._(
      engine: resolvedEngine,
      store: resolvedStore,
      importer: importer ?? SystemFileImporter(store: resolvedStore),
      export: export,
      library: library ??
          SqfliteLibraryRepository(
            store: resolvedStore,
            // Unawaited on purpose: opening the database must not delay the
            // first frame (requirements.md 3.1).
            database: _openDatabase(),
          ),
    );
  }

  static Future<Database> _openDatabase() async {
    final dir = await getApplicationSupportDirectory();
    return SqfliteLibraryRepository.open(p.join(dir.path, 'library.db'));
  }

  final PdfEngine engine;
  final DocumentStore store;
  final ExportService export;
  final FileImporter importer;
  final LibraryRepository library;

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
