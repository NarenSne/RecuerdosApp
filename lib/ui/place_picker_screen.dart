import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'widgets/place_map.dart';

/// Elegir un lugar tocando el mapa: ahí aparece el girasol.
class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({super.key, this.initial = const PlaceValue()});
  final PlaceValue initial;

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  static const _colombia = LatLng(4.65, -74.1);

  final _map = MapController();
  late final _name = TextEditingController(text: widget.initial.name);
  final _search = TextEditingController();
  late LatLng? _point = widget.initial.point;
  bool _nameIsAuto = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_point == null) _centerOnLastKnown();
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Si ya hay permiso de ubicación, empieza cerca de donde estás (sin preguntar).
  Future<void> _centerOnLastKnown() async {
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.always &&
          p != LocationPermission.whileInUse) {
        return;
      }
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted && _point == null) {
        _map.move(LatLng(pos.latitude, pos.longitude), 14);
      }
    } catch (_) {}
  }

  Future<void> _setPoint(LatLng p, {String? name}) async {
    setState(() => _point = p);
    if (name != null) {
      _name.text = name;
      _nameIsAuto = true;
      return;
    }
    if (_name.text.isNotEmpty && !_nameIsAuto) return;
    try {
      final marks = await placemarkFromCoordinates(p.latitude, p.longitude);
      if (marks.isEmpty || !mounted || _point != p) return;
      final m = marks.first;
      final parts = <String>{
        for (final s in [m.name, m.street, m.locality])
          if (s != null && s.trim().isNotEmpty) s.trim(),
      };
      if (parts.isNotEmpty) {
        _name.text = parts.take(2).join(', ');
        _nameIsAuto = true;
      }
    } catch (_) {
      // Sin nombre automático: se puede escribir a mano.
    }
  }

  Future<void> _myLocation() async {
    setState(() => _busy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _say('Activa la ubicación del teléfono para usar esta opción.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _say(
          'Sin permiso de ubicación. Puedes tocar el mapa para marcar el lugar.',
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final p = LatLng(pos.latitude, pos.longitude);
      _map.move(p, 16);
      await _setPoint(p);
    } catch (_) {
      _say(
        'No se pudo obtener tu ubicación. Toca el mapa para marcar el lugar.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final results = await locationFromAddress(q);
      if (results.isEmpty) {
        _say(
          'No encontramos "$q". Prueba con la ciudad, por ejemplo "$q, Medellín".',
        );
        return;
      }
      final p = LatLng(results.first.latitude, results.first.longitude);
      _map.move(p, 16);
      await _setPoint(p, name: q);
    } catch (_) {
      _say(
        'No encontramos "$q". Revisa la conexión o toca el mapa directamente.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    Navigator.of(context).pop(
      PlaceValue(
        name: _name.text.trim(),
        lat: _point?.latitude,
        lng: _point?.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSave = _point != null || _name.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Lugar')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _point ?? _colombia,
                    initialZoom: _point != null ? 16 : 5,
                    onTap: (_, p) => _setPoint(p),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    baseTiles(context),
                    if (_point != null)
                      MarkerLayer(
                        markers: [sunflowerMarker(_point!, size: 52)],
                      ),
                    mapAttribution(),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(10),
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _doSearch(),
                      decoration: InputDecoration(
                        hintText: 'Buscar un lugar o dirección',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 28,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Ir a mi ubicación',
                    onPressed: _busy ? null : _myLocation,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _point == null
                        ? 'Toca el mapa para plantar el girasol en el lugar.'
                        : 'Toca otro punto si quieres moverlo.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() => _nameIsAuto = false),
                    decoration: const InputDecoration(
                      labelText: 'Nombre del lugar',
                      hintText: 'Ej. El mirador donde nos conocimos',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: canSave ? _done : null,
                    child: const Text('Usar este lugar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
