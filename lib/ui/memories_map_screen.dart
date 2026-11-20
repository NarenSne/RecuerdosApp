import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import 'memories_screen.dart';
import 'theme.dart';
import 'widgets/empty_state.dart';
import 'widgets/place_map.dart';
import 'widgets/sunflower.dart';

/// Todos los recuerdos con lugar, cada uno con su girasol.
class MemoriesMapScreen extends StatelessWidget {
  const MemoriesMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final memories = context
        .watch<Repository>()
        .memories
        .where((m) => m.lat != null && m.lng != null)
        .toList();
    final points = [for (final m in memories) LatLng(m.lat!, m.lng!)];

    return Scaffold(
      appBar: AppBar(title: const Text('Nuestro mapa')),
      body: memories.isEmpty
          ? const EmptyState(
              icon: Icons.map_outlined,
              title: 'Todavía no hay girasoles',
              message:
                  'Cuando marques el lugar de un recuerdo en el mapa, aparecerá aquí.',
            )
          : FlutterMap(
              options: MapOptions(
                initialCenter: points.first,
                initialZoom: 14,
                initialCameraFit: points.length > 1
                    ? CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.fromLTRB(48, 80, 48, 48),
                        maxZoom: 16,
                      )
                    : null,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                baseTiles(context),
                MarkerLayer(
                  markers: [
                    for (final m in memories)
                      sunflowerMarker(
                        LatLng(m.lat!, m.lng!),
                        child: Tooltip(
                          message: m.title,
                          child: GestureDetector(
                            onTap: () => showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: true,
                              builder: (ctx) => SafeArea(
                                child: ListTile(
                                  title: Text(m.title),
                                  subtitle: Text(
                                    [
                                      formatDate(m.date),
                                      if (m.place.isNotEmpty) m.place,
                                    ].join(' · '),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    openMemory(context, m);
                                  },
                                ),
                              ),
                            ),
                            child: const Sunflower(),
                          ),
                        ),
                      ),
                  ],
                ),
                mapAttribution(),
              ],
            ),
    );
  }
}
