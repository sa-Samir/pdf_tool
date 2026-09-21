import 'package:flutter/material.dart';

/// App-wide settings.
///
/// Deliberately a plain [ChangeNotifier] for now: picking a state-management
/// package is a Phase 1 architecture decision (roadmap.md 5) and nothing here
/// needs one yet. Persistence lands with the settings store in Phase 4.
class AppSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  set themeMode(ThemeMode value) {
    if (value == _themeMode) return;
    _themeMode = value;
    notifyListeners();
  }

  /// Looks up the [AppSettings] above [context].
  static AppSettings of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'No AppSettingsScope found above this widget.');
    return scope!.notifier!;
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);
}
