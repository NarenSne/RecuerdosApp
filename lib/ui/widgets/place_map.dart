import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../place_picker_screen.dart';
import 'sunflower.dart';

/// Un lugar: nombre y punto en el mapa.
class PlaceValue {
  const PlaceValue({this.name = '', this.lat, this.lng});
  final String name;
  final double? lat;
  final double? lng;

  bool get hasPoint => lat != null && lng != null;
  bool get isEmpty => name.isEmpty && !hasPoint;
  LatLng? get point => hasPoint ? LatLng(lat!, lng!) : null;
}

/// Capa de mapa base: OpenStreetMap, sin clave de API.
///
/// Para publicar la app en las tiendas con muchos usuarios conviene cambiar a
/// un proveedor con clave (MapTiler, Stadia…): solo cambia esta URL.
TileLayer baseTiles(BuildContext context) => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.recuerditos.recuerditos',
);

Widget mapAttribution() => const RichAttributionWidget(
  alignment: AttributionAlignment.bottomLeft,
  attributions: [TextSourceAttribution('© colaboradores de OpenStreetMap')],
);

Marker sunflowerMarker(LatLng point, {double size = 44, Widget? child}) =>
    Marker(
      point: point,
      width: size,
      height: size * Sunflower.heightFactor,
      // La punta del tallo queda exactamente sobre el punto.
      alignment: Alignment.topCenter,
      child: child ?? Sunflower(size: size),
    );

/// Mapa pequeño, sin gestos, con el girasol en el lugar.
class MiniMap extends StatelessWidget {
  const MiniMap({super.key, required this.point, this.height = 160});
  final LatLng point;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: IgnorePointer(
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            baseTiles(context),
            MarkerLayer(markers: [sunflowerMarker(point, size: 40)]),
          ],
        ),
      ),
    );
  }
}

/// Campo de formulario: muestra el lugar elegido y abre el mapa al tocarlo.
class PlaceTile extends StatelessWidget {
  const PlaceTile({super.key, required this.value, required this.onChanged});

  final PlaceValue value;
  final ValueChanged<PlaceValue> onChanged;

  Future<void> _pick(BuildContext context) async {
    final result = await Navigator.of(context).push<PlaceValue>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlacePickerScreen(initial: value),
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = BorderRadius.circular(10);
    return Semantics(
      button: true,
      label: value.isEmpty ? 'Elegir lugar en el mapa' : 'Lugar: ${value.name}',
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: border,
          side: BorderSide(color: scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _pick(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.point != null)
                MiniMap(point: value.point!, height: 120),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 4, 14),
                child: Row(
                  children: [
                    Icon(Icons.place_outlined, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value.isEmpty
                            ? 'Marcar el lugar en el mapa'
                            : (value.name.isEmpty
                                  ? 'Punto en el mapa'
                                  : value.name),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: value.isEmpty ? scheme.onSurfaceVariant : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!value.isEmpty)
                      IconButton(
                        tooltip: 'Quitar lugar',
                        icon: const Icon(Icons.close),
                        onPressed: () => onChanged(const PlaceValue()),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.chevron_right,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
