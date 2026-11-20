import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/memory.dart';
import 'instagram_post_screen.dart';
import 'memories_screen.dart';
import 'memory_edit_screen.dart';
import 'theme.dart';
import 'widgets/media_view.dart';
import 'widgets/place_map.dart';

class MemoryDetailScreen extends StatelessWidget {
  const MemoryDetailScreen({super.key, required this.memoryId});
  final String memoryId;

  Future<void> _delete(BuildContext context, Memory memory) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar este recuerdo?'),
        content: const Text(
          'Se borrará con sus fotos y videos en este teléfono y en el de tu pareja. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).pop();
    await context.read<Repository>().deleteMemory(memory.id);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final memory = repo.memoryById(memoryId);
    if (memory == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Este recuerdo ya no existe.')),
      );
    }
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        actions: [
          FavoriteButton(memory: memory),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MemoryEditScreen(memory: memory),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Borrar',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, memory),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (memory.media.isNotEmpty) _Gallery(media: memory.media),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(memory.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.event_outlined,
                  text: formatDate(memory.date),
                ),
                if (memory.place.isNotEmpty || memory.lat != null)
                  _InfoRow(
                    icon: Icons.place_outlined,
                    text: memory.place.isEmpty
                        ? 'Ver en el mapa'
                        : memory.place,
                    onTap: () => openInMaps(
                      context,
                      place: memory.place,
                      lat: memory.lat,
                      lng: memory.lng,
                    ),
                  ),
                if (memory.lat != null && memory.lng != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: MiniMap(
                      point: PlaceValue(
                        lat: memory.lat,
                        lng: memory.lng,
                      ).point!,
                    ),
                  ),
                ],
                if (memory.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(memory.description, style: theme.textTheme.bodyLarge),
                ],
                if (memory.media.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            InstagramPostScreen(memoryId: memory.id),
                      ),
                    ),
                    icon: const Icon(Icons.grid_view_outlined),
                    label: const Text('Crear post para Instagram'),
                  ),
                ],
                if (memory.author.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Guardado por ${memory.author}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onTap != null ? theme.colorScheme.primary : null,
                decoration: onTap != null ? TextDecoration.underline : null,
                decorationColor: theme.colorScheme.primary,
              ),
            ),
          ),
          if (onTap != null)
            Icon(Icons.open_in_new, size: 16, color: theme.colorScheme.primary),
        ],
      ),
    );
    return onTap == null
        ? row
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Semantics(
              button: true,
              label: 'Abrir $text en el mapa',
              child: row,
            ),
          );
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.media});
  final List<MediaItem> media;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _page = 0;

  void _openFull(int index) => Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullScreenMedia(media: widget.media, initial: index),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: PageView.builder(
            itemCount: media.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _openFull(i),
              child: MediaThumb(item: media[i], cacheWidth: 1400),
            ),
          ),
        ),
        if (media.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_page + 1} de ${media.length}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
      ],
    );
  }
}

class _FullScreenMedia extends StatelessWidget {
  const _FullScreenMedia({required this.media, required this.initial});
  final List<MediaItem> media;
  final int initial;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repository>();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initial),
        itemCount: media.length,
        itemBuilder: (_, i) {
          final item = media[i];
          final file = repo.fileFor(item);
          if (!file.existsSync()) {
            return const Center(
              child: Text(
                'Este archivo todavía se está recibiendo.',
                style: TextStyle(color: Colors.white),
              ),
            );
          }
          if (item.isVideo) return VideoView(file: file);
          return InteractiveViewer(
            maxScale: 5,
            child: Center(child: Image.file(file)),
          );
        },
      ),
    );
  }
}
