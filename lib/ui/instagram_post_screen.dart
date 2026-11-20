import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import '../models/memory.dart';
import 'theme.dart';
import 'widgets/media_view.dart';

/// Instagram permite hasta 20 fotos o videos por carrusel.
const instagramMaxItems = 20;

/// Recorta una foto al centro en 4:5 (1080 × 1350), el formato vertical que
/// más espacio ocupa en el feed. Corre en otro hilo para no trabar la app.
void _cropTo4x5(String src, String out) {
  final decoded = img.decodeImage(File(src).readAsBytesSync());
  if (decoded == null) {
    File(src).copySync(out);
    return;
  }
  var im = img.bakeOrientation(decoded);
  const ratio = 4 / 5;
  final w = im.width, h = im.height;
  int cw, ch, x, y;
  if (w / h > ratio) {
    ch = h;
    cw = (h * ratio).round();
    x = (w - cw) ~/ 2;
    y = 0;
  } else {
    cw = w;
    ch = (w / ratio).round();
    x = 0;
    y = (h - ch) ~/ 2;
  }
  im = img.copyCrop(im, x: x, y: y, width: cw, height: ch);
  if (cw > 1080) {
    im = img.copyResize(
      im,
      width: 1080,
      height: 1350,
      interpolation: img.Interpolation.average,
    );
  }
  File(out).writeAsBytesSync(img.encodeJpg(im, quality: 92));
}

/// Corre el recorte en otro hilo. Es una función de nivel superior para que
/// el cierre solo capture las dos rutas (y no la pantalla).
Future<void> cropTo4x5InBackground(String src, String out) =>
    Isolate.run(() => _cropTo4x5(src, out));

/// Orden sugerido: la portada es la primera foto; después el resto en el
/// orden del recuerdo.
List<MediaItem> arrangeForInstagram(List<MediaItem> media) {
  final firstPhoto = media.where((m) => !m.isVideo).firstOrNull;
  return [
    if (firstPhoto != null) firstPhoto,
    ...media.where((m) => m != firstPhoto),
  ];
}

String captionFor(Memory m) => [
  m.title,
  if (m.description.isNotEmpty) m.description,
  [if (m.place.isNotEmpty) m.place, formatDate(m.date)].join(' · '),
].join('\n\n');

class InstagramPostScreen extends StatefulWidget {
  const InstagramPostScreen({
    super.key,
    required this.memoryId,
    this.justSaved = false,
  });

  final String memoryId;

  /// Se abrió automáticamente después de guardar el recuerdo.
  final bool justSaved;

  @override
  State<InstagramPostScreen> createState() => _InstagramPostScreenState();
}

class _InstagramPostScreenState extends State<InstagramPostScreen> {
  late final Memory? _memory = context.read<Repository>().memoryById(
    widget.memoryId,
  );
  late List<MediaItem> _order;
  final _excluded = <String>{};
  late final _caption = TextEditingController(
    text: _memory == null ? '' : captionFor(_memory),
  );
  final _pages = PageController();
  String? _busy;

  @override
  void initState() {
    super.initState();
    final repo = context.read<Repository>();
    final ready = (_memory?.media ?? const <MediaItem>[])
        .where((m) => repo.fileFor(m).existsSync())
        .toList();
    _order = arrangeForInstagram(ready);
    for (final m in _order.skip(instagramMaxItems)) {
      _excluded.add(m.id);
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _pages.dispose();
    super.dispose();
  }

  List<MediaItem> get _selected =>
      _order.where((m) => !_excluded.contains(m.id)).toList();

  void _toggle(MediaItem m) {
    setState(() {
      if (_excluded.contains(m.id)) {
        if (_selected.length >= instagramMaxItems) {
          _say('Instagram permite hasta $instagramMaxItems por publicación.');
          return;
        }
        _excluded.remove(m.id);
      } else if (_selected.length > 1) {
        _excluded.add(m.id);
      }
    });
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Deja los archivos listos, en orden, en una carpeta temporal.
  Future<List<({String path, bool isVideo})>> _prepare() async {
    final repo = context.read<Repository>();
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'instagram', widget.memoryId));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    final out = <({String path, bool isVideo})>[];
    final items = _selected;
    for (var i = 0; i < items.length; i++) {
      final m = items[i];
      setState(() => _busy = 'Preparando ${i + 1} de ${items.length}…');
      final src = repo.fileFor(m).path;
      final n = (i + 1).toString().padLeft(2, '0');
      if (m.isVideo) {
        final dst = p.join(dir.path, '$n.${m.ext}');
        await File(src).copy(dst);
        out.add((path: dst, isVideo: true));
      } else {
        final dst = p.join(dir.path, '$n.jpg');
        await cropTo4x5InBackground(src, dst);
        out.add((path: dst, isVideo: false));
      }
    }
    return out;
  }

  Future<void> _copyCaption({bool quiet = false}) async {
    await Clipboard.setData(ClipboardData(text: _caption.text));
    if (!quiet) _say('Texto copiado');
  }

  Future<void> _share(Rect origin) async {
    try {
      final files = await _prepare();
      await _copyCaption(quiet: true);
      if (!mounted) return;
      setState(() => _busy = null);
      _say('El texto quedó copiado: pégalo en Instagram.');
      await SharePlus.instance.share(
        ShareParams(
          files: [for (final f in files) XFile(f.path)],
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      debugPrint('Post de Instagram: $e');
      _say('No se pudo preparar el post. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _saveToPhotos() async {
    try {
      // Solo pide permiso para agregar, no para ver toda la fototeca.
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        _say('Sin permiso para guardar en Fotos. Actívalo en Ajustes.');
        return;
      }
      final files = await _prepare();
      setState(() => _busy = 'Guardando en Fotos…');
      for (final f in files) {
        if (f.isVideo) {
          await Gal.putVideo(f.path);
        } else {
          await Gal.putImage(f.path);
        }
      }
      await _copyCaption(quiet: true);
      _say('Guardado en Fotos, en orden. El texto quedó copiado.');
    } on GalException catch (e) {
      _say('No se pudo guardar en Fotos (${e.type.message}).');
    } catch (e) {
      debugPrint('Guardar en Fotos: $e');
      _say('No se pudo guardar en Fotos. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final memory = _memory;
    final selected = _selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post para Instagram'),
        actions: [
          if (widget.justSaved)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ahora no'),
            ),
        ],
      ),
      body: memory == null || _order.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Este recuerdo no tiene fotos ni videos listos para publicar.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : AbsorbPointer(
              absorbing: _busy != null,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (widget.justSaved)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'Recuerdo guardado. Organizamos las fotos y videos como carrusel: revisa el orden y publícalo si quieres.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  // Vista previa con el recorte real 4:5.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 4 / 5,
                        child: PageView.builder(
                          controller: _pages,
                          itemCount: selected.length,
                          onPageChanged: (_) => setState(() {}),
                          itemBuilder: (_, i) =>
                              MediaThumb(item: selected[i], cacheWidth: 1080),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      '${selected.length} ${selected.length == 1 ? 'elemento' : 'elementos'} · formato 4:5'
                      '${selected.any((m) => m.isVideo) ? ' · los videos los recorta Instagram al subirlos' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Orden', style: theme.textTheme.titleSmall),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                    child: Text(
                      'Toca para quitar o volver a poner. Mantén presionado y arrastra para cambiar el orden.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 100,
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _order.length,
                      onReorder: (from, to) => setState(() {
                        if (to > from) to--;
                        _order.insert(to, _order.removeAt(from));
                      }),
                      itemBuilder: (context, i) {
                        final m = _order[i];
                        final out = _excluded.contains(m.id);
                        final number = selected.indexOf(m) + 1;
                        return Padding(
                          key: ValueKey(m.id),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Semantics(
                            button: true,
                            label: out
                                ? 'Fuera del post. Tocar para incluir'
                                : 'Número $number del post. Tocar para quitar',
                            child: GestureDetector(
                              onTap: () => _toggle(m),
                              child: SizedBox(
                                width: 80,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: MediaThumb(
                                        item: m,
                                        cacheWidth: 240,
                                      ),
                                    ),
                                    if (out)
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: scheme.surface.withValues(
                                            alpha: 0.75,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.visibility_off,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      )
                                    else
                                      Positioned(
                                        left: 4,
                                        top: 4,
                                        child: CircleAvatar(
                                          radius: 11,
                                          backgroundColor: scheme.primary,
                                          child: Text(
                                            '$number',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: scheme.onPrimary,
                                                ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _caption,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 2200,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Texto del post',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_busy != null) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(_busy!, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                        ],
                        Builder(
                          builder: (btnContext) => FilledButton.icon(
                            onPressed: () {
                              final box =
                                  btnContext.findRenderObject() as RenderBox;
                              _share(box.localToGlobal(Offset.zero) & box.size);
                            },
                            icon: const Icon(Icons.ios_share),
                            label: const Text('Compartir en Instagram'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _saveToPhotos,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Guardar en Fotos'),
                        ),
                        TextButton(
                          onPressed: _copyCaption,
                          child: const Text('Copiar solo el texto'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
