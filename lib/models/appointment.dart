/// Una cita en el calendario de la app.
class Appointment {
  const Appointment({
    required this.id,
    required this.title,
    required this.start,
    required this.updatedAt,
    this.end,
    this.place = '',
    this.lat,
    this.lng,
    this.notes = '',
    this.author = '',
    this.deleted = false,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String place;
  final double? lat;
  final double? lng;
  final String notes;
  final String author;
  final int updatedAt;
  final bool deleted;

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'end_at': end?.millisecondsSinceEpoch,
    'place': place,
    'lat': lat,
    'lng': lng,
    'notes': notes,
    'author': author,
    'updated_at': updatedAt,
    'deleted': deleted ? 1 : 0,
  };

  factory Appointment.fromRow(Map<String, Object?> r) => Appointment(
    id: r['id'] as String,
    title: r['title'] as String,
    start: DateTime.fromMillisecondsSinceEpoch((r['start'] as num).toInt()),
    end: r['end_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((r['end_at'] as num).toInt()),
    place: (r['place'] as String?) ?? '',
    lat: (r['lat'] as num?)?.toDouble(),
    lng: (r['lng'] as num?)?.toDouble(),
    notes: (r['notes'] as String?) ?? '',
    author: (r['author'] as String?) ?? '',
    updatedAt: (r['updated_at'] as num).toInt(),
    deleted: r['deleted'] == 1 || r['deleted'] == true,
  );

  Appointment copyWith({int? updatedAt, bool? deleted}) => Appointment(
    id: id,
    title: title,
    start: start,
    end: end,
    place: place,
    lat: lat,
    lng: lng,
    notes: notes,
    author: author,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );
}
