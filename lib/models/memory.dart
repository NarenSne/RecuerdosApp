bool _bool(Object? v) => v == 1 || v == true;
double? _double(Object? v) => (v as num?)?.toDouble();
int _int(Object? v) => (v as num).toInt();

class MediaItem {
  const MediaItem({
    required this.id,
    required this.memoryId,
    required this.type,
    required this.ext,
    required this.position,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String memoryId;

  /// 'photo' o 'video'.
  final String type;
  final String ext;
  final int position;
  final int updatedAt;
  final bool deleted;

  bool get isVideo => type == 'video';
  String get fileName => '$id.$ext';

  Map<String, Object?> toRow() => {
    'id': id,
    'memory_id': memoryId,
    'type': type,
    'ext': ext,
    'position': position,
    'updated_at': updatedAt,
    'deleted': deleted ? 1 : 0,
  };

  factory MediaItem.fromRow(Map<String, Object?> r) => MediaItem(
    id: r['id'] as String,
    memoryId: r['memory_id'] as String,
    type: r['type'] as String,
    ext: r['ext'] as String,
    position: _int(r['position']),
    updatedAt: _int(r['updated_at']),
    deleted: _bool(r['deleted']),
  );
}

class Memory {
  const Memory({
    required this.id,
    required this.title,
    required this.date,
    required this.updatedAt,
    this.description = '',
    this.place = '',
    this.lat,
    this.lng,
    this.author = '',
    this.deleted = false,
    this.favoriteAt,
    this.media = const [],
  });

  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String place;
  final double? lat;
  final double? lng;

  /// Nombre de quien lo guardó por primera vez.
  final String author;
  final int updatedAt;
  final bool deleted;

  /// Cuándo se marcó como favorito (null si no lo es). Máximo 3 favoritos.
  final int? favoriteAt;
  bool get isFavorite => favoriteAt != null;

  /// Fotos y videos visibles, ordenados.
  final List<MediaItem> media;

  /// Portada: la primera foto; si solo hay videos, el primer video.
  MediaItem? get cover {
    for (final m in media) {
      if (!m.isVideo) return m;
    }
    return media.isEmpty ? null : media.first;
  }

  Memory copyWith({
    String? title,
    String? description,
    DateTime? date,
    String? place,
    double? Function()? lat,
    double? Function()? lng,
    int? Function()? favoriteAt,
    int? updatedAt,
  }) => Memory(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    date: date ?? this.date,
    place: place ?? this.place,
    lat: lat != null ? lat() : this.lat,
    lng: lng != null ? lng() : this.lng,
    author: author,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted,
    favoriteAt: favoriteAt != null ? favoriteAt() : this.favoriteAt,
    media: media,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'description': description,
    'date': date.millisecondsSinceEpoch,
    'place': place,
    'lat': lat,
    'lng': lng,
    'author': author,
    'updated_at': updatedAt,
    'deleted': deleted ? 1 : 0,
    'favorite_at': favoriteAt,
  };

  factory Memory.fromRow(
    Map<String, Object?> r, {
    List<MediaItem> media = const [],
  }) => Memory(
    id: r['id'] as String,
    title: r['title'] as String,
    description: (r['description'] as String?) ?? '',
    date: DateTime.fromMillisecondsSinceEpoch(_int(r['date'])),
    place: (r['place'] as String?) ?? '',
    lat: _double(r['lat']),
    lng: _double(r['lng']),
    author: (r['author'] as String?) ?? '',
    updatedAt: _int(r['updated_at']),
    deleted: _bool(r['deleted']),
    favoriteAt: (r['favorite_at'] as num?)?.toInt(),
    media: media,
  );
}
