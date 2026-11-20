import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Un "mes" o aniversario: la fecha en que cumplen [months] meses juntos.
class Milestone {
  const Milestone(this.months, this.date);

  final int months;
  final DateTime date;

  bool get isAnniversary => months % 12 == 0;
  int get years => months ~/ 12;

  /// "Cumplen 1 mes", "Cumplen 15 meses", "Cumplen 2 años".
  String get label {
    if (isAnniversary) {
      return years == 1 ? 'Cumplen 1 año' : 'Cumplen $years años';
    }
    return months == 1 ? 'Cumplen 1 mes' : 'Cumplen $months meses';
  }

  String get notificationTitle =>
      isAnniversary ? 'Feliz aniversario' : 'Feliz mes';

  String notificationBody(DateTime start) =>
      'Hoy ${label.toLowerCase()} juntos. Desde el '
      '${DateFormat("d 'de' MMMM 'de' y", 'es').format(start)}.';
}

/// El día del mes número [n] desde [start]. Si ese mes no tiene ese día
/// (ej. 31 de febrero), se usa el último día del mes.
DateTime monthiversary(DateTime start, int n) {
  final total = start.month - 1 + n;
  final year = start.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, math.min(start.day, lastDay));
}

/// Si [day] es un "mes" o aniversario, lo devuelve.
Milestone? milestoneOn(DateTime start, DateTime day) {
  final n = (day.year - start.year) * 12 + day.month - start.month;
  if (n < 1) return null;
  final d = monthiversary(start, n);
  return d.year == day.year && d.month == day.month && d.day == day.day
      ? Milestone(n, d)
      : null;
}

/// El próximo "mes" o aniversario desde hoy (incluye hoy).
Milestone nextMilestone(DateTime start, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  var n = math.max(1, (t.year - start.year) * 12 + t.month - start.month);
  while (true) {
    final d = monthiversary(start, n);
    if (!d.isBefore(t)) return Milestone(n, d);
    n++;
  }
}

/// "3 meses", "1 año y 2 meses", "2 años".
String timeTogether(DateTime start, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  var months = (t.year - start.year) * 12 + t.month - start.month;
  if (months > 0 && monthiversary(start, months).isAfter(t)) months--;
  if (months < 1) {
    final days = t
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    return days == 1 ? '1 día' : '$days días';
  }
  final y = months ~/ 12;
  final m = months % 12;
  final ys = y == 1 ? '1 año' : '$y años';
  final ms = m == 1 ? '1 mes' : '$m meses';
  if (y == 0) return ms;
  if (m == 0) return ys;
  return '$ys y $ms';
}
