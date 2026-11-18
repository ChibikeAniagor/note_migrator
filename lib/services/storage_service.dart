import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/migration_record.dart';

/// Local settings and export history. Note text is never written here.
class StorageService {
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  static const historyKey = 'migration_history';
  static const onboardingKey = 'onboarding_seen';

  bool get onboardingSeen => _prefs.getBool(onboardingKey) ?? false;

  Future<void> setOnboardingSeen() => _prefs.setBool(onboardingKey, true);

  List<MigrationRecord> readHistory() {
    final raw = _prefs.getString(historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) ?MigrationRecord.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> addRecord(MigrationRecord record) async {
    final next = [record, ...readHistory()].take(30).toList();
    await _prefs.setString(
      historyKey,
      jsonEncode([for (final item in next) item.toJson()]),
    );
  }
}
