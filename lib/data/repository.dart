import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/appointment.dart';
import '../models/memory.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();
int nowMs() => DateTime.now().millisecondsSinceEpoch;

const videoExtensions = {'mp4', 'mov', 'm4v', '3gp', 'avi', 'mkv', 'webm'};
bool isVideoPath(String path) => videoExtensions.contains(
  p.extension(path).replaceFirst('.', '').toLowerCase(),
);

/// Largo máximo del nombre de una persona.
const maxNameLength = 60;

final _safeMediaId = RegExp(r'^[A-Za-z0-9-]{1,64}$');
final _safeMediaExt = RegExp(r'^[a-z0-9]{1,5}$');

/// Un id y una extensión que solo pueden nombrar un archivo dentro de la
/// carpeta de fotos (nada de "../" ni separadores).
bool isSafeMediaName(String id, String ext) =>
    _safeMediaId.hasMatch(id) && _safeMediaExt.hasMatch(ext);

/// Extensión limpia para un archivo elegido en este teléfono.
String mediaExtensionFor(String path, {required bool isVideo}) {
  final ext = p
      .extension(path)
      .replaceFirst('.', '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (ext.isEmpty || ext.length > 5) return isVideo ? 'mp4' : 'jpg';
  return ext;
}

/// Convierte datos recibidos con tipos inesperados en [FormatException]: un
/// mensaje mal formado se descarta en vez de detener la sincronización.
T _parseIncoming<T>(String what, T Function() parse) {
  try {
    return parse();
  } on TypeError {
    throw FormatException('$what con formato inválido');
  } on ArgumentError {
    // Por ejemplo, una fecha fuera del rango que DateTime acepta.
    throw FormatException('$what con valores fuera de rango');
  }
}

/// El mayor valor que acepta DateTime.fromMillisecondsSinceEpoch.
const _maxEpochMs = 8640000000000000;

/// Un archivo recién elegido de la galería o la cámara.
class PickedMedia {
  const PickedMedia(this.path, {required this.isVideo});
  final String path;
  final bool isVideo;
}

/// Un cambio pendiente de enviar a la pareja.
class OutboxEntry {
  const OutboxEntry(this.id, this.kind, this.refType, this.refId);
  final int id;

  /// 'record' (datos de un recuerdo o cita) o 'file' (una foto o video).
  final String kind;
  final String refType;
  final String refId;
}

/// Todo lo que la app guarda vive aquí: una base SQLite y una carpeta con las
/// fotos y videos, ambas dentro del teléfono.
class Repository extends ChangeNotifier {
  Repository(this._db, this.mediaDir);

  final Database _db;
  final Directory mediaDir;

  /// Se llama después de cada cambio hecho en este teléfono.
  VoidCallback? onLocalChange;

  List<Memory> _memories = const [];
  List<Appointment> _appointments = const [];
  String _myName = '';
  DateTime? _anniversary;

  List<Memory> get memories => _memories;
  List<Appointment> get appointments => _appointments;
  String get myName => _myName;

  /// Apodo que esta persona le puso a su pareja. Solo vive en este teléfono.
  String get partnerNickname => _partnerNickname;
  String _partnerNickname = '';

  /// El día en que empezaron. Se comparte con la pareja.
  DateTime? get anniversary => _anniversary;

  static const maxFavorites = 3;

  /// Favoritos en el orden en que se marcaron (máximo 3).
  List<Memory> get favorites {
    final favs = _memories.where((m) => m.isFavorite).toList()
      ..sort((a, b) => a.favoriteAt!.compareTo(b.favoriteAt!));
    return favs.take(maxFavorites).toList();
  }

  static Future<Database> openDb(String path, {DatabaseFactory? factory}) {
    return (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('ALTER TABLE memories ADD COLUMN favorite_at INTEGER');
    }
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE memories(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        date INTEGER NOT NULL,
        place TEXT NOT NULL DEFAULT '',
        lat REAL,
        lng REAL,
        author TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        favorite_at INTEGER
      )''');
    await db.execute('''
      CREATE TABLE media(
        id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL,
        type TEXT NOT NULL,
        ext TEXT NOT NULL,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX media_memory ON media(memory_id)');
    await db.execute('''
      CREATE TABLE appointments(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        start INTEGER NOT NULL,
        end_at INTEGER,
        place TEXT NOT NULL DEFAULT '',
        lat REAL,
        lng REAL,
        notes TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        ref_type TEXT NOT NULL,
        ref_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(kind, ref_type, ref_id)
      )''');
    await db.execute(
      'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  Future<void> close() => _db.close();

  Future<void> init() async {
    _myName = await getSetting('my_name') ?? '';
    _partnerNickname = await getSetting('partner_nickname') ?? '';
    await load();
  }

  Future<void> load() async {
    final mediaRows = await _db.query(
      'media',
      where: 'deleted = 0',
      orderBy: 'position',
    );
    final byMemory = <String, List<MediaItem>>{};
    for (final r in mediaRows) {
      final m = MediaItem.fromRow(r);
      (byMemory[m.memoryId] ??= []).add(m);
    }
    final memRows = await _db.query(
      'memories',
      where: 'deleted = 0',
      orderBy: 'date DESC, updated_at DESC',
    );
    _memories = [
      for (final r in memRows)
        Memory.fromRow(r, media: byMemory[r['id']] ?? const []),
    ];
    final apRows = await _db.query(
      'appointments',
      where: 'deleted = 0',
      orderBy: 'start',
    );
    _appointments = apRows.map(Appointment.fromRow).toList();
    final ann = await getSetting('anniversary');
    _anniversary = ann == null || ann.isEmpty
        ? null
        : DateTime.fromMillisecondsSinceEpoch(int.parse(ann));
    notifyListeners();
  }

  Memory? memoryById(String id) {
    for (final m in _memories) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// El archivo de una foto o video. Siempre queda dentro de [mediaDir].
  File fileFor(MediaItem m) =>
      File(p.join(mediaDir.path, p.basename(m.fileName)));

  Future<void> setPartnerNickname(String nickname) async {
    _partnerNickname = nickname.trim();
    await setSetting('partner_nickname', _partnerNickname);
    notifyListeners();
  }

  Future<void> setMyName(String name) async {
    _myName = name.trim();
    await setSetting('my_name', _myName);
    // Así la pareja ve el nombre nuevo aunque no se guarde nada más.
    await _enqueue(_db, 'record', 'hello', 'me');
    notifyListeners();
    onLocalChange?.call();
  }

  // ---------------------------------------------------------------------------
  // Recuerdos

  Future<void> saveMemory(
    Memory memory, {
    List<PickedMedia> added = const [],
    Set<String> removed = const {},
  }) async {
    final ts = nowMs();
    final last = await _db.query(
      'media',
      columns: ['position'],
      where: 'memory_id = ?',
      whereArgs: [memory.id],
      orderBy: 'position DESC',
      limit: 1,
    );
    var pos = last.isEmpty ? 0 : (last.first['position'] as int) + 1;

    final newItems = <MediaItem>[];
    for (final a in added) {
      final item = MediaItem(
        id: newId(),
        memoryId: memory.id,
        type: a.isVideo ? 'video' : 'photo',
        ext: mediaExtensionFor(a.path, isVideo: a.isVideo),
        position: pos++,
        updatedAt: ts,
      );
      await File(a.path).copy(fileFor(item).path);
      newItems.add(item);
    }

    await _db.transaction((txn) async {
      await txn.insert(
        'memories',
        memory.copyWith(updatedAt: ts).toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final item in newItems) {
        await txn.insert('media', item.toRow());
      }
      for (final id in removed) {
        await txn.update(
          'media',
          {'deleted': 1, 'updated_at': ts},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'outbox',
          where: "kind = 'file' AND ref_id = ?",
          whereArgs: [id],
        );
      }
      await _enqueue(txn, 'record', 'memory', memory.id);
      for (final item in newItems) {
        await _enqueue(txn, 'file', 'media', item.id);
      }
    });
    for (final id in removed) {
      await _deleteMediaFile(id);
    }
    await load();
    onLocalChange?.call();
  }

  Future<void> deleteMemory(String id) async {
    final ts = nowMs();
    final mediaIds = (await _db.query(
      'media',
      columns: ['id'],
      where: 'memory_id = ?',
      whereArgs: [id],
    )).map((r) => r['id'] as String).toList();
    await _db.transaction((txn) async {
      await txn.update(
        'memories',
        {'deleted': 1, 'updated_at': ts},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'media',
        {'deleted': 1, 'updated_at': ts},
        where: 'memory_id = ? AND deleted = 0',
        whereArgs: [id],
      );
      for (final mid in mediaIds) {
        await txn.delete(
          'outbox',
          where: "kind = 'file' AND ref_id = ?",
          whereArgs: [mid],
        );
      }
      await _enqueue(txn, 'record', 'memory', id);
    });
    for (final mid in mediaIds) {
      await _deleteMediaFile(mid);
    }
    await load();
    onLocalChange?.call();
  }

  Future<void> _deleteMediaFile(String mediaId) async {
    final m = await mediaById(mediaId);
    if (m == null) return;
    final f = fileFor(m);
    if (await f.exists()) await f.delete();
  }

  /// Marca o quita un favorito. Devuelve false si ya hay 3 favoritos.
  Future<bool> toggleFavorite(String id) async {
    final memory = memoryById(id);
    if (memory == null) return false;
    if (!memory.isFavorite && favorites.length >= maxFavorites) return false;
    await saveMemory(
      memory.copyWith(favoriteAt: () => memory.isFavorite ? null : nowMs()),
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // Mes y aniversario

  Future<void> setAnniversary(DateTime? date) async {
    final day = date == null ? null : DateTime(date.year, date.month, date.day);
    await _db.transaction((txn) async {
      await _setSetting(
        txn,
        'anniversary',
        day == null ? '' : '${day.millisecondsSinceEpoch}',
      );
      await _setSetting(txn, 'anniversary_updated', '${nowMs()}');
      await _enqueue(txn, 'record', 'couple', 'couple');
    });
    await load();
    onLocalChange?.call();
  }

  // ---------------------------------------------------------------------------
  // Citas

  Future<void> saveAppointment(Appointment a) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'appointments',
        a.copyWith(updatedAt: nowMs()).toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _enqueue(txn, 'record', 'appointment', a.id);
    });
    await load();
    onLocalChange?.call();
  }

  Future<void> deleteAppointment(String id) async {
    await _db.transaction((txn) async {
      await txn.update(
        'appointments',
        {'deleted': 1, 'updated_at': nowMs()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _enqueue(txn, 'record', 'appointment', id);
    });
    await load();
    onLocalChange?.call();
  }

  // ---------------------------------------------------------------------------
  // Sincronización

  Future<void> _enqueue(
    DatabaseExecutor ex,
    String kind,
    String refType,
    String refId,
  ) {
    // REPLACE le da un id nuevo: si el envío anterior está en curso, este
    // cambio no se pierde cuando ese envío borre su propia entrada.
    return ex.insert('outbox', {
      'kind': kind,
      'ref_type': refType,
      'ref_id': refId,
      'created_at': nowMs(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<OutboxEntry>> pendingOutbox({int limit = 20}) async {
    final rows = await _db.query('outbox', orderBy: 'id', limit: limit);
    return [
      for (final r in rows)
        OutboxEntry(
          r['id'] as int,
          r['kind'] as String,
          r['ref_type'] as String,
          r['ref_id'] as String,
        ),
    ];
  }

  Future<int> outboxCount() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM outbox'),
      ) ??
      0;

  Future<void> removeOutbox(int id) =>
      _db.delete('outbox', where: 'id = ?', whereArgs: [id]);

  Future<void> clearOutbox() => _db.delete('outbox');

  /// Pone en cola todo lo guardado, para que la pareja reciba lo que ya había
  /// antes de conectarse. Primero los datos y después las fotos y videos.
  Future<void> enqueueEverything() async {
    await _db.transaction((txn) async {
      // Primero un saludo con el nombre: así quien creó el código sabe que la
      // pareja ya se conectó aunque todavía no tenga nada guardado.
      await _enqueue(txn, 'record', 'hello', 'me');
      for (final r in await txn.query('memories', columns: ['id'])) {
        await _enqueue(txn, 'record', 'memory', r['id'] as String);
      }
      for (final r in await txn.query('appointments', columns: ['id'])) {
        await _enqueue(txn, 'record', 'appointment', r['id'] as String);
      }
      final couple = await txn.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['anniversary_updated'],
      );
      if (couple.isNotEmpty) {
        await _enqueue(txn, 'record', 'couple', 'couple');
      }
      for (final r in await txn.query(
        'media',
        columns: ['id'],
        where: 'deleted = 0',
        orderBy: 'position',
      )) {
        await _enqueue(txn, 'file', 'media', r['id'] as String);
      }
    });
  }

  Future<MediaItem?> mediaById(String id) async {
    final rows = await _db.query('media', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : MediaItem.fromRow(rows.first);
  }

  /// Datos de un recuerdo o cita listos para enviar (incluye borrados).
  Future<Map<String, Object?>?> exportRecord(String type, String id) async {
    // Solo lleva el nombre (en el sobre); no cambia nada al recibirlo.
    if (type == 'hello') return const {};
    if (type == 'memory') {
      final rows = await _db.query(
        'memories',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return null;
      final media = await _db.query(
        'media',
        where: 'memory_id = ?',
        whereArgs: [id],
      );
      return {...rows.first, 'media': media};
    }
    if (type == 'appointment') {
      final rows = await _db.query(
        'appointments',
        where: 'id = ?',
        whereArgs: [id],
      );
      return rows.isEmpty ? null : rows.first;
    }
    if (type == 'couple') {
      final updated = await getSetting('anniversary_updated');
      if (updated == null) return null;
      final ann = await getSetting('anniversary');
      return {
        'anniversary': ann == null || ann.isEmpty ? null : int.parse(ann),
        'updated_at': int.parse(updated),
      };
    }
    return null;
  }

  /// Aplica un cambio recibido de la pareja. Gana la versión más reciente.
  ///
  /// Lanza [FormatException] si los datos no tienen la forma esperada. Los
  /// tipos desconocidos (de una versión más nueva de la app) se ignoran.
  Future<void> applyRecord(String type, Map<String, dynamic> data) async {
    switch (type) {
      case 'memory':
        await _applyMemory(data);
      case 'appointment':
        final incoming = _parseIncoming(
          'Cita',
          () => Appointment.fromRow(data),
        );
        await _db.transaction((txn) async {
          if (await _isNewer(
            txn,
            'appointments',
            incoming.id,
            incoming.updatedAt,
          )) {
            await txn.insert(
              'appointments',
              incoming.toRow(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
      case 'couple':
        final (updated, ann) = _parseIncoming(
          'Fecha de aniversario',
          () => (
            (data['updated_at'] as num).toInt(),
            (data['anniversary'] as num?)?.toInt(),
          ),
        );
        // Se valida aquí porque la fecha se convierte en DateTime al cargar.
        if (ann != null && ann.abs() > _maxEpochMs) {
          throw const FormatException('Fecha de aniversario fuera de rango');
        }
        await _db.transaction((txn) async {
          final rows = await txn.query(
            'settings',
            where: 'key = ?',
            whereArgs: ['anniversary_updated'],
          );
          final local = rows.isEmpty
              ? -1
              : int.tryParse(rows.first['value'] as String) ?? -1;
          if (updated > local) {
            await _setSetting(txn, 'anniversary', ann == null ? '' : '$ann');
            await _setSetting(txn, 'anniversary_updated', '$updated');
          }
        });
      // 'hello' solo trae el nombre (en el sobre) y no cambia datos.
    }
  }

  Future<void> _applyMemory(Map<String, dynamic> data) async {
    final incoming = _parseIncoming('Recuerdo', () => Memory.fromRow(data));
    final rawMedia = data['media'] ?? const [];
    if (rawMedia is! List) {
      throw const FormatException('Recuerdo con formato inválido');
    }
    final media = <MediaItem>[];
    for (final raw in rawMedia) {
      final m = _parseIncoming(
        'Foto o video',
        () => MediaItem.fromRow(Map<String, Object?>.from(raw as Map)),
      );
      // Se ignoran archivos con nombres peligrosos o de otro recuerdo.
      if (!isSafeMediaName(m.id, m.ext) ||
          m.memoryId != incoming.id ||
          (m.type != 'photo' && m.type != 'video')) {
        debugPrint('Foto o video ignorado: datos no válidos');
        continue;
      }
      media.add(m);
    }

    final filesToDelete = <MediaItem>[];
    await _db.transaction((txn) async {
      if (await _isNewer(txn, 'memories', incoming.id, incoming.updatedAt)) {
        await txn.insert(
          'memories',
          incoming.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final m in media) {
        if (await _isNewer(txn, 'media', m.id, m.updatedAt)) {
          await txn.insert(
            'media',
            m.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (m.deleted) filesToDelete.add(m);
        }
      }
    });
    for (final m in filesToDelete) {
      final f = fileFor(m);
      if (await f.exists()) await f.delete();
    }
  }

  Future<bool> _isNewer(
    DatabaseExecutor ex,
    String table,
    String id,
    int updatedAt,
  ) async {
    final rows = await ex.query(
      table,
      columns: ['updated_at'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty || updatedAt > (rows.first['updated_at'] as int);
  }

  /// Guarda una foto o video recibido. Puede llegar antes que su recuerdo.
  Future<void> storeIncomingFile(
    String mediaId,
    String ext,
    List<int> bytes,
  ) async {
    if (!isSafeMediaName(mediaId, ext)) {
      throw const FormatException('Archivo con nombre inválido');
    }
    final existing = await mediaById(mediaId);
    if (existing != null && existing.deleted) return;
    await File(
      p.join(mediaDir.path, '$mediaId.$ext'),
    ).writeAsBytes(bytes, flush: true);
  }

  // ---------------------------------------------------------------------------
  // Ajustes

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String? value) =>
      _setSetting(_db, key, value);

  Future<void> _setSetting(
    DatabaseExecutor ex,
    String key,
    String? value,
  ) async {
    if (value == null) {
      await ex.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await ex.insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
