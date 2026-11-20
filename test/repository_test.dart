import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:recuerditos/data/repository.dart';
import 'package:recuerditos/models/memory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late Directory media;
  late Repository repo;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('repo');
    media = Directory(p.join(root.path, 'media'))..createSync();
    final db = await Repository.openDb(
      p.join(root.path, 'db.sqlite'),
      factory: databaseFactoryFfi,
    );
    repo = Repository(db, media);
    await repo.init();
  });

  tearDown(() async {
    await repo.close();
    root.deleteSync(recursive: true);
  });

  /// Un recuerdo tal como lo enviaría la pareja.
  Map<String, dynamic> incomingMemory(
    String id, {
    List<Map<String, Object?>> media = const [],
    Object? title,
  }) => {
    'id': id,
    'title': title ?? 'Playa',
    'description': '',
    'date': DateTime(2026, 1, 10).millisecondsSinceEpoch,
    'place': '',
    'lat': null,
    'lng': null,
    'author': 'Beto',
    'updated_at': 100,
    'deleted': 0,
    'favorite_at': null,
    'media': media,
  };

  Map<String, Object?> incomingMedia(
    String id,
    String memoryId, {
    String ext = 'jpg',
    String type = 'photo',
    int deleted = 0,
  }) => {
    'id': id,
    'memory_id': memoryId,
    'type': type,
    'ext': ext,
    'position': 0,
    'updated_at': 100,
    'deleted': deleted,
  };

  group('nombres de archivo', () {
    test('acepta ids y extensiones normales', () {
      expect(isSafeMediaName(newId(), 'jpg'), isTrue);
      expect(isSafeMediaName('abc-123', 'heic'), isTrue);
      expect(isSafeMediaName('a', 'mp4'), isTrue);
    });

    test('rechaza rutas, separadores y extensiones raras', () {
      expect(isSafeMediaName('../../recuerditos', 'db'), isFalse);
      expect(isSafeMediaName('a/b', 'jpg'), isFalse);
      expect(isSafeMediaName('..', 'jpg'), isFalse);
      expect(isSafeMediaName('', 'jpg'), isFalse);
      expect(isSafeMediaName('a', ''), isFalse);
      expect(isSafeMediaName('a', 'JPG'), isFalse);
      expect(isSafeMediaName('a', 'jpg/..'), isFalse);
      expect(isSafeMediaName('a', 'mpeg42'), isFalse);
      expect(isSafeMediaName('x' * 65, 'jpg'), isFalse);
    });

    test('la extensión de un archivo elegido se limpia', () {
      expect(mediaExtensionFor('/f/IMG_1.JPG', isVideo: false), 'jpg');
      expect(mediaExtensionFor('/f/clip.MOV', isVideo: true), 'mov');
      expect(mediaExtensionFor('/f/sin_extension', isVideo: false), 'jpg');
      expect(mediaExtensionFor('/f/sin_extension', isVideo: true), 'mp4');
      expect(mediaExtensionFor('/f/a.jpg_large', isVideo: false), 'jpg');
      expect(mediaExtensionFor('/f/a.he-ic', isVideo: false), 'heic');
    });

    test('fileFor nunca sale de la carpeta de fotos', () {
      const evil = MediaItem(
        id: '../../fuera',
        memoryId: 'm',
        type: 'photo',
        ext: 'db',
        position: 0,
        updatedAt: 0,
      );
      expect(p.dirname(repo.fileFor(evil).path), media.path);
    });
  });

  group('datos recibidos de la pareja', () {
    test(
      'un archivo con ruta peligrosa no borra nada fuera de la carpeta',
      () async {
        final victim = File(p.join(root.path, 'importante.db'))
          ..writeAsStringSync('no me borres');
        final memoryId = newId();
        final goodId = newId();
        await repo.applyRecord(
          'memory',
          incomingMemory(
            memoryId,
            media: [
              incomingMedia('../importante', memoryId, ext: 'db', deleted: 1),
              incomingMedia(goodId, memoryId),
            ],
          ),
        );
        expect(victim.existsSync(), isTrue);
        final saved = repo.memoryById(memoryId);
        expect(saved, isNull, reason: 'aún no se recargó');
        await repo.load();
        expect(repo.memoryById(memoryId)!.media.map((m) => m.id), [goodId]);
      },
    );

    test(
      'ignora fotos que dicen ser de otro recuerdo o de tipo desconocido',
      () async {
        final memoryId = newId();
        await repo.applyRecord(
          'memory',
          incomingMemory(
            memoryId,
            media: [
              incomingMedia(newId(), 'otro-recuerdo'),
              incomingMedia(newId(), memoryId, type: 'ejecutable'),
            ],
          ),
        );
        await repo.load();
        expect(repo.memoryById(memoryId)!.media, isEmpty);
      },
    );

    test('datos con tipos equivocados lanzan FormatException', () async {
      await expectLater(
        repo.applyRecord('memory', incomingMemory(newId(), title: 5)),
        throwsFormatException,
      );
      await expectLater(
        repo.applyRecord('memory', {
          ...incomingMemory(newId()),
          'media': 'no-es-lista',
        }),
        throwsFormatException,
      );
      await expectLater(
        repo.applyRecord('memory', {
          ...incomingMemory(newId()),
          'media': ['no-es-mapa'],
        }),
        throwsFormatException,
      );
      await expectLater(
        repo.applyRecord('appointment', {'id': 1}),
        throwsFormatException,
      );
      await expectLater(
        repo.applyRecord('couple', {'updated_at': 'ayer'}),
        throwsFormatException,
      );
      await repo.load();
      expect(repo.memories, isEmpty);
    });

    test(
      'una fecha imposible no entra a la base (la app seguiría abriendo)',
      () async {
        await expectLater(
          repo.applyRecord('memory', {
            ...incomingMemory(newId()),
            'date': 9000000000000000,
          }),
          throwsFormatException,
        );
        await expectLater(
          repo.applyRecord('couple', {
            'updated_at': 5,
            'anniversary': 9000000000000000,
          }),
          throwsFormatException,
        );
        await repo.load();
        expect(repo.anniversary, isNull);
        expect(repo.memories, isEmpty);
      },
    );

    test('tipos desconocidos y el saludo no cambian nada', () async {
      await repo.applyRecord('hello', const {});
      await repo.applyRecord('algo-de-una-version-nueva', const {'x': 1});
      await repo.load();
      expect(repo.memories, isEmpty);
      expect(repo.appointments, isEmpty);
    });

    test('un cambio más viejo no reemplaza uno más nuevo', () async {
      final id = newId();
      await repo.applyRecord('memory', {
        ...incomingMemory(id, title: 'Nuevo'),
        'updated_at': 200,
      });
      await repo.applyRecord('memory', {
        ...incomingMemory(id, title: 'Viejo'),
        'updated_at': 150,
      });
      await repo.load();
      expect(repo.memoryById(id)!.title, 'Nuevo');
    });

    test('storeIncomingFile rechaza nombres peligrosos', () async {
      await expectLater(
        repo.storeIncomingFile('../fuera', 'db', [1, 2, 3]),
        throwsFormatException,
      );
      await expectLater(
        repo.storeIncomingFile('ok', 'j/pg', [1]),
        throwsFormatException,
      );
      expect(File(p.join(root.path, 'fuera.db')).existsSync(), isFalse);

      final id = newId();
      await repo.storeIncomingFile(id, 'jpg', [1, 2, 3]);
      expect(File(p.join(media.path, '$id.jpg')).readAsBytesSync(), [1, 2, 3]);
    });
  });

  group('recuerdos en este teléfono', () {
    Future<Memory> saveWithPhoto() async {
      final photo = File(p.join(root.path, 'foto.JPG'))
        ..writeAsBytesSync([9, 9, 9]);
      final memory = Memory(
        id: newId(),
        title: 'Cumple',
        date: DateTime(2026, 3, 1),
        updatedAt: 0,
      );
      await repo.saveMemory(
        memory,
        added: [PickedMedia(photo.path, isVideo: false)],
      );
      return repo.memoryById(memory.id)!;
    }

    test(
      'guardar copia la foto con un nombre seguro y la pone en cola',
      () async {
        final saved = await saveWithPhoto();
        final item = saved.media.single;
        expect(item.ext, 'jpg');
        expect(repo.fileFor(item).readAsBytesSync(), [9, 9, 9]);
        final queued = await repo.pendingOutbox();
        expect(
          queued.map((e) => '${e.kind}:${e.refType}'),
          containsAll(['record:memory', 'file:media']),
        );
      },
    );

    test('quitar una foto borra el archivo y su envío pendiente', () async {
      final saved = await saveWithPhoto();
      final item = saved.media.single;
      await repo.saveMemory(saved, removed: {item.id});
      expect(repo.fileFor(item).existsSync(), isFalse);
      expect(repo.memoryById(saved.id)!.media, isEmpty);
      final queued = await repo.pendingOutbox();
      expect(queued.where((e) => e.kind == 'file'), isEmpty);
    });

    test('borrar un recuerdo borra sus archivos y avisa a la pareja', () async {
      final saved = await saveWithPhoto();
      final file = repo.fileFor(saved.media.single);
      await repo.deleteMemory(saved.id);
      expect(file.existsSync(), isFalse);
      expect(repo.memories, isEmpty);
      final exported = await repo.exportRecord('memory', saved.id);
      expect(exported!['deleted'], 1);
      final queued = await repo.pendingOutbox();
      expect(queued.where((e) => e.kind == 'file'), isEmpty);
      expect(queued.where((e) => e.refType == 'memory'), hasLength(1));
    });

    test('el mismo cambio en cola no se duplica', () async {
      final saved = await saveWithPhoto();
      await repo.saveMemory(saved.copyWith(title: 'Otro'));
      await repo.saveMemory(saved.copyWith(title: 'Otro más'));
      final memoryEntries = (await repo.pendingOutbox()).where(
        (e) => e.refType == 'memory',
      );
      expect(memoryEntries, hasLength(1));
    });

    test('ajustes: null borra el valor', () async {
      await repo.setSetting('x', 'uno');
      expect(await repo.getSetting('x'), 'uno');
      await repo.setSetting('x', null);
      expect(await repo.getSetting('x'), isNull);
    });

    test('el nombre propio se limpia y se avisa a la pareja', () async {
      await repo.setMyName('  Ana  ');
      expect(repo.myName, 'Ana');
      final queued = await repo.pendingOutbox();
      expect(queued.where((e) => e.refType == 'hello'), hasLength(1));
    });
  });
}
