import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../data/repository.dart';
import '../models/memory.dart';
import 'instagram_post_screen.dart';
import 'theme.dart';
import 'widgets/media_view.dart';
import 'widgets/place_map.dart';

class MemoryEditScreen extends StatefulWidget {
  const MemoryEditScreen({super.key, this.memory, this.initialDate});

  /// Si viene, se edita; si no, es un recuerdo nuevo.
  final Memory? memory;
  final DateTime? initialDate;

  @override
  State<MemoryEditScreen> createState() => _MemoryEditScreenState();
}

class _MemoryEditScreenState extends State<MemoryEditScreen> {
  final _picker = ImagePicker();
  late final _title = TextEditingController(text: widget.memory?.title);
  late final _description = TextEditingController(
    text: widget.memory?.description,
  );
  late DateTime _date =
      widget.memory?.date ??
      widget.initialDate ??
      DateUtils.dateOnly(DateTime.now());
  late PlaceValue _place = PlaceValue(
    name: widget.memory?.place ?? '',
    lat: widget.memory?.lat,
    lng: widget.memory?.lng,
  );
  late final List<MediaItem> _existing = [...?widget.memory?.media];
  final _removed = <String>{};
  final _added = <PickedMedia>[];
  bool _saving = false;
  String? _titleError;

  bool get _isNew => widget.memory == null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _addMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir fotos y videos'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Grabar video'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    try {
      final files = <XFile>[];
      switch (choice) {
        case 'gallery':
          files.addAll(
            await _picker.pickMultipleMedia(imageQuality: 85, maxWidth: 2560),
          );
        case 'photo':
          final f = await _picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
            maxWidth: 2560,
          );
          if (f != null) files.add(f);
        case 'video':
          final f = await _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(minutes: 3),
          );
          if (f != null) files.add(f);
      }
      var tooBig = 0;
      final picked = <PickedMedia>[];
      for (final f in files) {
        final isVideo = choice == 'video' || isVideoPath(f.path);
        if (isVideo && await File(f.path).length() > AppConfig.maxShareBytes) {
          tooBig++;
        }
        picked.add(PickedMedia(f.path, isVideo: isVideo));
      }
      // La persona pudo salir de la pantalla mientras elegía.
      if (!mounted) return;
      setState(() => _added.addAll(picked));
      if (tooBig > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tooBig == 1
                  ? 'Ese video pesa más de 45 MB: se guarda en tu teléfono, pero no se enviará a tu pareja.'
                  : '$tooBig videos pesan más de 45 MB: se guardan en tu teléfono, pero no se enviarán a tu pareja.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir la cámara o la galería. Revisa los permisos de la app en Ajustes.',
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Ponle un nombre a este recuerdo');
      return;
    }
    setState(() => _saving = true);
    final repo = context.read<Repository>();
    final base =
        widget.memory ??
        Memory(
          id: newId(),
          title: title,
          date: _date,
          author: repo.myName,
          updatedAt: 0,
        );
    try {
      await repo.saveMemory(
        base.copyWith(
          title: title,
          description: _description.text.trim(),
          date: _date,
          place: _place.name,
          lat: () => _place.lat,
          lng: () => _place.lng,
        ),
        added: _added,
        removed: _removed,
      );
      if (!mounted) return;
      if (_added.isNotEmpty) {
        // Recién guardado con fotos o videos nuevos: armamos el post.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                InstagramPostScreen(memoryId: base.id, justSaved: true),
          ),
        );
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Guardar recuerdo: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo guardar el recuerdo. Revisa que haya espacio en el teléfono e intenta de nuevo.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _existing.where((m) => !_removed.contains(m.id)).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nuevo recuerdo' : 'Editar recuerdo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _saving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton(onPressed: _save, child: const Text('Guardar')),
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
              labelText: 'Qué pasó',
              hintText: 'Ej. Nuestra primera cita',
              errorText: _titleError,
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha',
                prefixIcon: Icon(Icons.event_outlined),
              ),
              child: Text(formatDate(_date)),
            ),
          ),
          const SizedBox(height: 16),
          PlaceTile(
            value: _place,
            onChanged: (v) => setState(() => _place = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Cuéntalo',
              hintText: 'Lo que no quieres olvidar de ese día',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          Text('Fotos y videos', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in visible)
                _Tile(
                  onRemove: () => setState(() => _removed.add(m.id)),
                  child: MediaThumb(item: m, cacheWidth: 300),
                ),
              for (final m in _added)
                _Tile(
                  onRemove: () => setState(() => _added.remove(m)),
                  child: PickedThumb(media: m),
                ),
              _AddTile(onTap: _addMedia),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child, required this.onRemove});
  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Quitar',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              iconSize: 18,
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Agregar fotos o videos',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined, color: scheme.primary),
              const SizedBox(height: 4),
              Text(
                'Agregar',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
