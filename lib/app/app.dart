import 'package:flutter/material.dart';

import '../core/services/app_services.dart';
import '../core/theme/app_theme.dart';
import '../features/home/home_page.dart';
import 'app_settings.dart';

class PdfToolboxApp extends StatefulWidget {
  const PdfToolboxApp({super.key, this.services});

  /// Injected in tests; built on demand in the real app.
  final AppServices? services;

  @override
  State<PdfToolboxApp> createState() => _PdfToolboxAppState();
}

class _PdfToolboxAppState extends State<PdfToolboxApp> {
  final _settings = AppSettings();
  late final AppServices _services = widget.services ?? AppServices();

  @override
  void initState() {
    super.initState();
    // Requirements.md 5.2: sweep anything a crash left behind. After the first
    // frame and unawaited, so it never delays launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _services.store.sweepWorkspaces();
      // Requirements.md 4: entries whose file has gone are pruned at launch.
      _services.library.pruneMissing();
    });
  }

  @override
  void dispose() {
    _settings.dispose();
    _services.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppServicesScope(
      services: _services,
      child: AppSettingsScope(
        settings: _settings,
        child: AnimatedBuilder(
          animation: _settings,
          builder: (context, _) => MaterialApp(
            title: 'PDF Toolbox',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: _settings.themeMode,
            home: const HomePage(),
          ),
        ),
      ),
    );
  }
}
