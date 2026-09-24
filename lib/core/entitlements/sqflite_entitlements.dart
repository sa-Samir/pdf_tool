import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'entitlements.dart';

/// Entitlements backed by the app's own database.
///
/// Counts are local and survive reinstall only as far as the database does.
/// Requirements.md 9 accepts that: the alternative is an account, which costs
/// more in conversion than the leakage costs in revenue.
class SqfliteEntitlements implements Entitlements {
  SqfliteEntitlements({
    required FutureOr<Database> database,
    bool isPremium = false,
  })  : _db = Future.value(database),
        _isPremium = isPremium;

  final Future<Database> _db;
  final bool _isPremium;
  final _notifier = _Notifier();

  static const table = 'tool_usage';

  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE $table (
        tool_id TEXT PRIMARY KEY,
        used INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  @override
  bool get isPremium => _isPremium;

  @override
  Listenable get changes => _notifier;

  @override
  Future<ToolAllowance> allowanceFor(String toolId) async {
    final rows = await (await _db).query(
      table,
      where: 'tool_id = ?',
      whereArgs: [toolId],
    );
    return ToolAllowance(
      toolId: toolId,
      used: rows.isEmpty ? 0 : rows.first['used']! as int,
      isPremium: _isPremium,
    );
  }

  @override
  Future<void> recordUse(String toolId) async {
    if (_isPremium) return;
    final db = await _db;
    // One statement, so two operations finishing together cannot both read
    // the same count and write the same value back.
    await db.rawInsert(
      'INSERT INTO $table (tool_id, used) VALUES (?, 1) '
      'ON CONFLICT(tool_id) DO UPDATE SET used = used + 1',
      [toolId],
    );
    _notifier.ping();
  }

  @override
  Future<void> refundUse(String toolId) async {
    if (_isPremium) return;
    final db = await _db;
    // MAX guards the floor inside the statement, so a refund that races
    // another cannot drive the count negative.
    await db.rawUpdate(
      'UPDATE $table SET used = MAX(used - 1, 0) WHERE tool_id = ?',
      [toolId],
    );
    _notifier.ping();
  }
}

/// A ChangeNotifier that can be pinged from outside it.
class _Notifier extends ChangeNotifier {
  void ping() => notifyListeners();
}
