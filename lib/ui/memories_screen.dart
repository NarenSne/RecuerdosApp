import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/milestones.dart';
import '../data/repository.dart';
import '../models/memory.dart';
import '../sync/sync_service.dart';
import 'memories_map_screen.dart';
import 'memory_detail_screen.dart';
import 'memory_edit_screen.dart';
import 'theme.dart';
import 'widgets/couple_title.dart';
import 'widgets/empty_state.dart';
import 'widgets/media_view.dart';

/// Marca o quita un favorito, avisando si ya hay 3.
Future<void> toggleFavorite(BuildContext context, Memory memory) async {
  final ok = await context.read<Repository>().toggleFavorite(memory.id);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ya tienen 3 favoritos. Quita uno para agregar este.'),
      ),
    );
  }
}

void openMemory(BuildContext context, Memory m) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => MemoryDetailScreen(memoryId: m.id)));

class MemoriesScreen extends StatelessWidget {
  const MemoriesScreen({super.key});

  void _new(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const MemoryEditScreen()));

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final memories = repo.memories;
    final favorites = repo.favorites;
    final sync = context.read<SyncService>();
    final theme = Theme.of(context);
    final start = repo.anniversary;
    final today = start == null ? null : milestoneOn(start, DateTime.now());

    final items = <Widget>[
      if (today != null) _TodayBanner(milestone: today),
      _SectionHeader(
        title: 'Favoritos',
        trailing: favorites.isEmpty ? null : '${favorites.length} de 3',
      ),
      if (favorites.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Toca la estrella de un recuerdo para tenerlo aquí. Pueden elegir hasta 3.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        )
      else
        _FavoritesRow(favorites: favorites),
    ];
    DateTime? month;
    for (final m in memories) {
      if (month == null ||
          month.year != m.date.year ||
          month.month != m.date.month) {
        month = DateTime(m.date.year, m.date.month);
        items.add(_SectionHeader(title: formatMonthYear(month)));
      }
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: MemoryCard(memory: m),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 92,
        title: const CoupleTitle(),
        actions: [
          if (memories.isNotEmpty)
            IconButton(
              tooltip: 'Ver en el mapa',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MemoriesMapScreen()),
              ),
            ),
        ],
      ),
      floatingActionButton: memories.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _new(context),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo recuerdo'),
            ),
      body: memories.isEmpty
          ? Column(
              children: [
                if (today != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _TodayBanner(milestone: today),
                  ),
                Expanded(
                  child: EmptyState(
                    icon: Icons.photo_album_outlined,
                    title: 'Aún no hay recuerdos',
                    message:
                        'Guarda el primero: qué pasó, cuándo, dónde y las fotos o videos de ese día. Todo se queda en este teléfono.',
                    action: FilledButton.icon(
                      onPressed: () => _new(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Guardar un recuerdo'),
                    ),
                  ),
                ),
              ],
            )
          : RefreshIndicator(
              onRefresh: sync.syncNow,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: items,
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayBanner extends StatelessWidget {
  const _TodayBanner({required this.milestone});
  final Milestone milestone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.favorite, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              milestone.isAnniversary
                  ? 'Feliz aniversario. Hoy ${milestone.label.toLowerCase()}.'
                  : 'Feliz mes. Hoy ${milestone.label.toLowerCase()}.',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritesRow extends StatelessWidget {
  const _FavoritesRow({required this.favorites});
  final List<Memory> favorites;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: i < favorites.length
                ? InkWell(
                    onTap: () => openMemory(context, favorites[i]),
                    borderRadius: BorderRadius.circular(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: favorites[i].cover == null
                                ? ColoredBox(
                                    color: theme.colorScheme.secondaryContainer,
                                    child: Icon(
                                      Icons.star,
                                      color: theme
                                          .colorScheme
                                          .onSecondaryContainer,
                                    ),
                                  )
                                : MediaThumb(
                                    item: favorites[i].cover!,
                                    cacheWidth: 400,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          favorites[i].title,
                          style: theme.textTheme.labelMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  )
                : AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Icon(
                        Icons.star_border,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

class MemoryCard extends StatelessWidget {
  const MemoryCard({super.key, required this.memory});
  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cover = memory.cover;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openMemory(context, memory),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cover != null)
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaThumb(item: cover),
                    if (memory.media.length > 1)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            child: Text(
                              '${memory.media.length} archivos',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memory.title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            memory.place.isEmpty
                                ? formatDate(memory.date)
                                : '${formatDate(memory.date)} · ${memory.place}',
                            style: muted,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (cover == null &&
                              memory.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              memory.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  FavoriteButton(memory: memory),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.memory});
  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final fav = memory.isFavorite;
    return IconButton(
      tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
      isSelected: fav,
      icon: const Icon(Icons.star_border),
      selectedIcon: Icon(Icons.star, color: Colors.amber.shade700),
      onPressed: () => toggleFavorite(context, memory),
    );
  }
}
