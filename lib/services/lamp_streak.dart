// PATCH_S170_MAGIC_FEATURES
// Studio Lamp: one dot lights per consecutive day with an export. Local only.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LampInfo {
  final int streak; // consecutive days, 0 when the chain is broken
  final int total; // lifetime exports
  final bool litToday;
  const LampInfo(this.streak, this.total, this.litToday);
}

class LampStreak {
  static final ValueNotifier<LampInfo?> info = ValueNotifier<LampInfo?>(null);
  static const _kLast = 'lamp_last_day';
  static const _kStreak = 'lamp_streak';
  static const _kTotal = 'lamp_total';

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime? _parse(String? s) {
    if (s == null) return null;
    final p = s.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final today = _day(DateTime.now());
      final last = _parse(p.getString(_kLast));
      var streak = p.getInt(_kStreak) ?? 0;
      final gap = last == null ? 999 : today.difference(last).inDays;
      if (gap > 1) streak = 0; // chain broken
      info.value = LampInfo(streak, p.getInt(_kTotal) ?? 0, gap == 0);
    } catch (_) {
      info.value ??= const LampInfo(0, 0, false);
    }
  }

  /// Call after a successful export.
  static Future<LampInfo> lightUp() async {
    try {
      final p = await SharedPreferences.getInstance();
      final today = _day(DateTime.now());
      final last = _parse(p.getString(_kLast));
      var streak = p.getInt(_kStreak) ?? 0;
      final total = (p.getInt(_kTotal) ?? 0) + 1;
      final gap = last == null ? 999 : today.difference(last).inDays;
      if (gap == 0) {
        streak = streak < 1 ? 1 : streak;
      } else if (gap == 1) {
        streak += 1;
      } else {
        streak = 1;
      }
      await p.setString(_kLast, _key(today));
      await p.setInt(_kStreak, streak);
      await p.setInt(_kTotal, total);
      final r = LampInfo(streak, total, true);
      info.value = r;
      return r;
    } catch (_) {
      return info.value ?? const LampInfo(0, 0, true);
    }
  }

  /// A message for the days worth marking, null otherwise.
  static String? milestoneMessage(int streak) => switch (streak) {
        3 => 'ثلاثة أيام متتالية — سراجك يتوهّج ✨ ثبّتك الله',
        7 => 'أسبوعٌ كامل! اكتمل سراجك 🪔 بارك الله في عملك',
        14 => 'أسبوعان من النور المتواصل — جزاك الله خيرًا',
        30 => 'شهرٌ كامل من العطاء! تقبّل الله منك 🌙',
        100 => 'مئة يوم! سراجٌ لا ينطفئ — نفع الله بك',
        _ => null,
      };
}
