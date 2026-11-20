import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../data/milestones.dart';
import '../data/repository.dart';
import '../models/appointment.dart';
import '../models/memory.dart';
import 'appointment_edit_screen.dart';
import 'memory_detail_screen.dart';
import 'theme.dart';
import 'widgets/media_view.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateUtils.dateOnly(DateTime.now());
  CalendarFormat _format = CalendarFormat.month;

  void _newAppointment() {
    final now = DateTime.now();
    // Por defecto, la próxima hora en punto del día elegido.
    final hour = sameDay(_selected, now) ? (now.hour + 1).clamp(0, 23) : 19;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppointmentEditScreen(
          initialStart: DateTime(
            _selected.year,
            _selected.month,
            _selected.day,
            hour,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final start = repo.anniversary;
    List<Object> eventsFor(DateTime day) => [
      if (start != null) ?milestoneOn(start, day),
      ...repo.appointments.where((a) => sameDay(a.start, day)),
      ...repo.memories.where((m) => sameDay(m.date, day)),
    ];

    final dayEvents = eventsFor(_selected);
    final dayAppointments = dayEvents.whereType<Appointment>().toList();
    final dayMemories = dayEvents.whereType<Memory>().toList();
    final dayMilestone = dayEvents.whereType<Milestone>().firstOrNull;
    final now = DateTime.now();
    final upcoming = repo.appointments
        .where((a) => a.start.isAfter(now) && !sameDay(a.start, _selected))
        .take(3)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _focused = DateTime.now();
              _selected = DateUtils.dateOnly(_focused);
            }),
            child: const Text('Hoy'),
          ),
        ],
      ),
      // Etiqueta propia: las pestañas viven juntas en un IndexedStack y dos
      // botones con la etiqueta por defecto rompen la animación al cambiar
      // de pantalla.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-nueva-cita',
        onPressed: _newAppointment,
        icon: const Icon(Icons.add),
        label: const Text('Nueva cita'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          TableCalendar<Object>(
            locale: 'es',
            firstDay: DateTime(1950),
            lastDay: DateTime(2100, 12, 31),
            focusedDay: _focused,
            selectedDayPredicate: (d) => sameDay(d, _selected),
            calendarFormat: _format,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Mes',
              CalendarFormat.twoWeeks: '2 semanas',
              CalendarFormat.week: 'Semana',
            },
            startingDayOfWeek: StartingDayOfWeek.monday,
            eventLoader: eventsFor,
            onDaySelected: (selected, focused) => setState(() {
              _selected = DateUtils.dateOnly(selected);
              _focused = focused;
            }),
            onFormatChanged: (f) => setState(() => _format = f),
            onPageChanged: (f) => _focused = f,
            headerStyle: HeaderStyle(
              titleTextFormatter: (d, _) => formatMonthYear(d),
              titleTextStyle: theme.textTheme.titleMedium!,
              formatButtonShowsNext: false,
              formatButtonTextStyle: theme.textTheme.labelMedium!,
              formatButtonDecoration: BoxDecoration(
                border: Border.all(color: scheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              todayDecoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(color: scheme.onPrimaryContainer),
              selectedDecoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: TextStyle(color: scheme.onPrimary),
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                if (events.isEmpty) return null;
                final hasCita = events.any((e) => e is Appointment);
                final hasMemory = events.any((e) => e is Memory);
                final hasMilestone = events.any((e) => e is Milestone);
                return Positioned(
                  bottom: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasMilestone)
                        Icon(Icons.favorite, size: 8, color: scheme.error),
                      if (hasCita) _Dot(color: scheme.primary),
                      if (hasMemory) _Dot(color: scheme.tertiary),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                _Dot(color: scheme.primary),
                const SizedBox(width: 4),
                Text('Cita', style: theme.textTheme.labelSmall),
                const SizedBox(width: 12),
                _Dot(color: scheme.tertiary),
                const SizedBox(width: 4),
                Text('Recuerdo', style: theme.textTheme.labelSmall),
                if (start != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.favorite, size: 8, color: scheme.error),
                  const SizedBox(width: 4),
                  Text('Mes o aniversario', style: theme.textTheme.labelSmall),
                ],
              ],
            ),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              formatDayLong(_selected),
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (dayEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Nada agendado este día.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (dayMilestone != null)
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.favorite, color: scheme.onErrorContainer),
              ),
              title: Text(dayMilestone.label),
              subtitle: Text(
                dayMilestone.isAnniversary
                    ? 'Aniversario'
                    : 'Desde el ${formatDate(start!)}',
              ),
            ),
          for (final a in dayAppointments) _AppointmentTile(appointment: a),
          for (final m in dayMemories)
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: m.cover == null
                      ? ColoredBox(
                          color: scheme.tertiaryContainer,
                          child: Icon(
                            Icons.photo_album_outlined,
                            color: scheme.onTertiaryContainer,
                          ),
                        )
                      : MediaThumb(item: m.cover!, cacheWidth: 150),
                ),
              ),
              title: Text(m.title),
              subtitle: Text(m.place.isEmpty ? 'Recuerdo' : m.place),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MemoryDetailScreen(memoryId: m.id),
                ),
              ),
            ),
          if (upcoming.isNotEmpty) ...[
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Próximas citas', style: theme.textTheme.titleMedium),
            ),
            for (final a in upcoming)
              _AppointmentTile(appointment: a, showDate: true),
          ],
        ],
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.appointment, this.showDate = false});
  final Appointment appointment;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final theme = Theme.of(context);
    final time = a.end == null
        ? formatTime(a.start)
        : '${formatTime(a.start)} – ${formatTime(a.end!)}';
    final details = [
      if (showDate) formatDate(a.start),
      if (!showDate) time,
      if (a.place.isNotEmpty) a.place,
    ].join(' · ');
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          formatTime(a.start),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(a.title),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AppointmentEditScreen(appointment: a),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
