import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/repository.dart';
import '../../models/memory.dart';

/// Miniatura de una foto o video ya guardado.
class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, required this.item, this.cacheWidth = 800});

  final MediaItem item;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final file = context.read<Repository>().fileFor(item);
    final scheme = Theme.of(context).colorScheme;
    if (!file.existsSync()) {
      return _Placeholder(
        icon: Icons.cloud_download_outlined,
        label: 'Recibiendo…',
        color: scheme.surfaceContainerHighest,
      );
    }
    if (item.isVideo) {
      return _Placeholder(
        icon: Icons.play_circle_outline,
        label: 'Video',
        color: scheme.secondaryContainer,
      );
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      errorBuilder: (_, __, ___) => _Placeholder(
        icon: Icons.broken_image_outlined,
        label: 'No se puede mostrar',
        color: scheme.surfaceContainerHighest,
      ),
    );
  }
}

/// Miniatura de un archivo recién elegido (todavía no guardado).
class PickedThumb extends StatelessWidget {
  const PickedThumb({super.key, required this.media});
  final PickedMedia media;

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      return _Placeholder(
        icon: Icons.play_circle_outline,
        label: 'Video',
        color: Theme.of(context).colorScheme.secondaryContainer,
      );
    }
    return Image.file(File(media.path), fit: BoxFit.cover, cacheWidth: 300);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final onColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return ColoredBox(
      color: color,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: onColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: onColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reproductor sencillo: toca para reproducir o pausar.
class VideoView extends StatefulWidget {
  const VideoView({super.key, required this.file});
  final File file;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final VideoPlayerController _c;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.file(widget.file)
      ..addListener(_onTick)
      ..initialize()
          .then((_) {
            if (mounted) setState(() => _ready = true);
          })
          .catchError((_) {
            if (mounted) setState(() => _failed = true);
          });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Text(
          'No se pudo reproducir este video.',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    final playing = _c.value.isPlaying;
    return GestureDetector(
      onTap: () => playing ? _c.pause() : _c.play(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _c.value.aspectRatio,
              child: VideoPlayer(_c),
            ),
          ),
          if (!playing)
            Semantics(
              button: true,
              label: 'Reproducir video',
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.play_arrow, size: 40, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(_c, allowScrubbing: true),
          ),
        ],
      ),
    );
  }
}
