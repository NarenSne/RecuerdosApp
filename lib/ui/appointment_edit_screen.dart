import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/appointment.dart';
import 'theme.dart';
import 'widgets/place_map.dart';

class AppointmentEditScreen extends StatefulWidget {
  const AppointmentEditScreen({super.key, this.appointment, this.initialStart});

  final Appointment? appointment;
  final DateTime? initialStart;

  @override
  State<AppointmentEditScreen> createState() => _AppointmentEditScreenState();
}

class _AppointmentEditScreenState extends State<AppointmentEditScreen> {
  late final _title = TextEditingController(text: widget.appointment?.title);
  late final _notes = TextEditingController(text: widget.appointment?.notes);
  late DateTime _day = DateUtils.dateOnly(
    widget.appointment?.start ?? widget.initialStart ?? DateTime.now(),
  );
  late TimeOfDay _start = TimeOfDay.fromDateTime(
    widget.appointment?.start ?? widget.initialStart ?? DateTime.now(),
  );
  late TimeOfDay? _end = widget.appointment?.end == null
      ? null
      : TimeOfDay.fromDateTime(widget.appointment!.end!);
  late PlaceValue _place = PlaceValue(
    name: widget.appointment?.place ?? '',
    lat: widget.appointment?.lat,
    lng: widget.appointment?.lng,
  );
  String? _titleError;
  bool _saving = false;

  bool get _isNew => widget.appointment == null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d != null) setState(() => _day = d);
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: _start);
    if (t != null) setState(() => _start = t);
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(
      context: context,
      initialTime:
          _end ??
          TimeOfDay(hour: (_start.hour + 1) % 24, minute: _start.minute),
    );
    if (t != null) setState(() => _end = t);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Escribe qué van a hacer');
      return;
    }
    final start = _at(_start);
    var end = _end == null ? null : _at(_end!);
    // Si termina "antes" de empezar, es que termina al día siguiente.
    if (end != null && !end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    setState(() => _saving = true);
    final repo = context.read<Repository>();
    final old = widget.appointment;
    await repo.saveAppointment(
      Appointment(
        id: old?.id ?? newId(),
        title: title,
        start: start,
        end: end,
        place: _place.name,
        lat: _place.lat,
        lng: _place.lng,
        notes: _notes.text.trim(),
        author: old?.author ?? repo.myName,
        updatedAt: 0,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar esta cita?'),
        content: const Text(
          'Se quitará del calendario en este teléfono y en el de tu pareja.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar cita'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<Repository>().deleteAppointment(widget.appointment!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.appointment;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nueva cita' : 'Cita'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Quitar cita',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _title,
            autofocus: _isNew,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
            decoration: InputDecoration(
              labelText: 'Qué van a hacer',
              hintText: 'Ej. Cena de aniversario',
              errorText: _titleError,
            ),
          ),
          const SizedBox(height: 16),
          PlaceTile(
            value: _place,
            onChanged: (v) => setState(() => _place = v),
          ),
          const SizedBox(height: 16),
          _PickerField(
            label: 'Día',
            icon: Icons.event_outlined,
            value: formatDayLong(_day),
            onTap: _pickDay,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PickerField(
                  label: 'Empieza',
                  icon: Icons.schedule,
                  value: formatTime(_at(_start)),
                  onTap: _pickStart,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickerField(
                  label: 'Termina',
                  icon: Icons.schedule_outlined,
                  value: _end == null ? 'Opcional' : formatTime(_at(_end!)),
                  onTap: _pickEnd,
                  onClear: _end == null
                      ? null
                      : () => setState(() => _end = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notas',
              hintText: 'Reserva, qué llevar, código de vestimenta…',
              alignLabelWithHint: true,
            ),
          ),
          if (a != null && a.author.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Agendada por ${a.author}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (a != null && (a.place.isNotEmpty || a.lat != null)) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  openInMaps(context, place: a.place, lat: a.lat, lng: a.lng),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Ver en el mapa'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  tooltip: 'Quitar hora de fin',
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
        ),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
