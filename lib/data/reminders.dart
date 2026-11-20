import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'milestones.dart';
import 'repository.dart';

/// Programa los recordatorios de "mes" y aniversario en este teléfono.
///
/// Se programan los próximos 24 a las 9:00 y se reprograman cada vez que la
/// fecha cambia o se abre la app, así nunca se acaban.
class ReminderService extends ChangeNotifier {
  ReminderService(this.repo);

  final Repository repo;
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _baseId = 1000;
  static const _count = 24;
  static const hour = 9;

  bool _ready = false;
  bool _enabled = true;
  String? _scheduledKey;
  Future<void> _queue = Future.value();

  bool get enabled => _enabled;

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Si no se puede leer la zona horaria, se usa UTC.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _enabled = await repo.getSetting('reminders') != 'off';
    _ready = true;
    repo.addListener(_schedule);
    _schedule();
  }

  /// Pide permiso para mostrar notificaciones. Devuelve si se concedió.
  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return false;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await repo.setSetting('reminders', value ? 'on' : 'off');
    notifyListeners();
    _schedule();
  }

  void _schedule() {
    if (!_ready) return;
    _queue = _queue.then((_) => _reschedule()).catchError((_) {});
  }

  Future<void> _reschedule() async {
    final start = repo.anniversary;
    final today = DateTime.now();
    final key =
        '${start?.millisecondsSinceEpoch}|$_enabled|'
        '${today.year}-${today.month}-${today.day}';
    if (key == _scheduledKey) return;
    // La clave se guarda al final: si algo falla a mitad, se reintenta en el
    // próximo cambio en vez de quedar sin recordatorios.
    _scheduledKey = null;

    for (var i = 0; i < _count; i++) {
      await _plugin.cancel(id: _baseId + i);
    }
    if (start == null || !_enabled) {
      _scheduledKey = key;
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mes_y_aniversario',
        'Mes y aniversario',
        channelDescription: 'Recordatorio cada mes y en el aniversario',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final now = tz.TZDateTime.now(tz.local);
    var id = _baseId;
    for (var n = 1; id < _baseId + _count && n < 2400; n++) {
      final d = monthiversary(start, n);
      final at = tz.TZDateTime(tz.local, d.year, d.month, d.day, hour);
      if (!at.isAfter(now)) continue;
      final m = Milestone(n, d);
      await _plugin.zonedSchedule(
        id: id++,
        scheduledDate: at,
        title: m.notificationTitle,
        body: m.notificationBody(start),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    _scheduledKey = key;
  }

  @override
  void dispose() {
    repo.removeListener(_schedule);
    super.dispose();
  }
}
