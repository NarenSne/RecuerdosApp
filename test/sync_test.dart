import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:recuerditos/data/repository.dart';
import 'package:recuerditos/models/appointment.dart';
import 'package:recuerditos/models/memory.dart';
import 'package:recuerditos/sync/couple_crypto.dart';
import 'package:recuerditos/sync/mailbox_transport.dart';
import 'package:recuerditos/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Buzón en memoria que imita las reglas de supabase/schema.sql.
class FakeServer {
  final rows =
      <({String id, String couple, String sender, MailboxMessage msg})>[];
  final blobs = <String, Uint8List>{};
  final members = <String, Set<String>>{};
  final invites = <String, ({String payload, String by, DateTime expires})>{};

  /// Simula que la red falla al descargar archivos para esta persona.
  String? failDownloadsFor;
  var _n = 0;
  String nextId() => '${_n++}';
}

class FakeTransport implements MailboxTransport {
  FakeTransport(this.server, this.user);
  final FakeServer server;
  final String user;

  @override
  Future<void> connect(String coupleId) async =>
      (server.members[coupleId] ??= {}).add(user);

  void _check(String coupleId) {
    if (!(server.members[coupleId]?.contains(user) ?? false)) {
      throw StateError('no es miembro');
    }
  }

  @override
  Future<void> send({
    required String coupleId,
    required String kind,
    required String payload,
    Uint8List? blob,
  }) async {
    _check(coupleId);
    String? path;
    if (blob != null) {
      path = '$coupleId/${server.nextId()}';
      server.blobs[path] = blob;
    }
    final id = server.nextId();
    server.rows.add((
      id: id,
      couple: coupleId,
      sender: user,
      msg: MailboxMessage(
        id: id,
        kind: kind,
        payload: payload,
        objectPath: path,
      ),
    ));
  }

  @override
  Future<List<MailboxMessage>> fetch(String coupleId, {int limit = 20}) async {
    _check(coupleId);
    return server.rows
        .where((r) => r.couple == coupleId && r.sender != user)
        .take(limit)
        .map((r) => r.msg)
        .toList();
  }

  @override
  Future<Uint8List?> download(String objectPath) async {
    if (server.failDownloadsFor == user) {
      throw const SyncException('Sin conexión a internet.');
    }
    return server.blobs[objectPath];
  }

  @override
  Future<void> createInvite({
    required String lookupHash,
    required String sealedSecret,
    required Duration validFor,
  }) async {
    server.invites[lookupHash] = (
      payload: sealedSecret,
      by: user,
      expires: DateTime.now().add(validFor),
    );
  }

  @override
  Future<String?> claimInvite(String lookupHash) async {
    final i = server.invites[lookupHash];
    if (i == null || i.by == user || i.expires.isBefore(DateTime.now())) {
      return null;
    }
    server.invites.remove(lookupHash);
    return i.payload;
  }

  @override
  Future<void> ack(MailboxMessage message) async {
    server.rows.removeWhere((r) => r.id == message.id);
    if (message.objectPath != null) server.blobs.remove(message.objectPath);
  }
}

final _open = <(Repository, SyncService)>[];

Future<(Repository, SyncService)> device(
  FakeServer server,
  String user,
  Directory root,
) async {
  final dir = Directory(p.join(root.path, user))..createSync();
  final media = Directory(p.join(dir.path, 'media'))..createSync();
  final db = await Repository.openDb(
    p.join(dir.path, 'db.sqlite'),
    factory: databaseFactoryFfi,
  );
  final repo = Repository(db, media);
  await repo.init();
  await repo.setMyName(user);
  final sync = SyncService(
    repo: repo,
    transport: FakeTransport(server, user),
    maxShareBytes: 1000,
  );
  await sync.init();
  _open.add((repo, sync));
  return (repo, sync);
}

void main() {
  sqfliteFfiInit();
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('recuerditos'));
  tearDown(() async {
    for (final (repo, sync) in _open) {
      sync.dispose();
      await repo.close();
    }
    _open.clear();
    root.deleteSync(recursive: true);
  });

  test('el código de pareja se puede leer y cifra/descifra', () async {
    final s = PairSecret.generate();
    final parsed = PairSecret.tryParse('  ${s.encode()}\n')!;
    final a = await CoupleCrypto.fromSecret(s);
    final b = await CoupleCrypto.fromSecret(parsed);
    expect(a.coupleId, b.coupleId);
    expect(a.coupleId, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await b.decryptText(await a.encryptText('hola')), 'hola');

    final other = await CoupleCrypto.fromSecret(PairSecret.generate());
    final sealed = await a.encryptText('x');
    await expectLater(other.decryptText(sealed), throwsA(anything));
    expect(PairSecret.tryParse('RCD1-corto'), isNull);
    expect(PairSecret.tryParse('hola'), isNull);
  });

  test('dos teléfonos comparten recuerdos, fotos y citas', () async {
    final server = FakeServer();
    final (repoA, syncA) = await device(server, 'Ana', root);
    final (repoB, syncB) = await device(server, 'Beto', root);

    // Ana guarda un recuerdo con una foto antes de emparejarse.
    final photo = File(p.join(root.path, 'foto.jpg'))
      ..writeAsBytesSync(List.generate(200, (i) => i % 256));
    final bigVideo = File(p.join(root.path, 'grande.mp4'))
      ..writeAsBytesSync(List.filled(5000, 1));
    await repoA.saveMemory(
      Memory(
        id: newId(),
        title: 'Primer viaje',
        date: DateTime(2026, 2, 14),
        place: 'Cartagena',
        author: 'Ana',
        updatedAt: 0,
      ),
      added: [
        PickedMedia(photo.path, isVideo: false),
        PickedMedia(bigVideo.path, isVideo: true),
      ],
    );

    final invite = await syncA.createInvite();
    expect(syncA.lastError, isNull);
    expect(syncA.paired, isTrue);
    await syncB.joinWithInvite(invite.code.display.toLowerCase());
    expect(syncB.lastError, isNull);
    expect(syncB.paired, isTrue);
    // El código es de un solo uso.
    expect(server.invites, isEmpty);

    expect(repoB.memories, hasLength(1));
    final m = repoB.memories.single;
    expect(m.title, 'Primer viaje');
    expect(m.place, 'Cartagena');
    expect(m.media, hasLength(2));
    final photoItem = m.media.firstWhere((x) => !x.isVideo);
    expect(repoB.fileFor(photoItem).readAsBytesSync(), photo.readAsBytesSync());
    // El video supera el límite: se queda solo en el teléfono de Ana.
    expect(syncA.skippedTooBig, 1);
    expect(
      repoB.fileFor(m.media.firstWhere((x) => x.isVideo)).existsSync(),
      isFalse,
    );
    expect(syncB.partnerName, 'Ana');

    // Beto agenda una cita; Ana la recibe.
    final cita = Appointment(
      id: newId(),
      title: 'Cena',
      start: DateTime(2026, 12, 1, 20),
      place: 'Casa',
      author: 'Beto',
      updatedAt: 0,
    );
    await repoB.saveAppointment(cita);
    await syncB.syncNow();
    await syncA.syncNow();
    expect(repoA.appointments.single.title, 'Cena');
    expect(syncA.partnerName, 'Beto');

    // Ana edita el recuerdo y quita la foto; Beto lo ve y la foto se borra.
    final local = repoA.memories.single;
    await repoA.saveMemory(
      local.copyWith(title: 'Primer viaje juntos'),
      removed: {photoItem.id},
    );
    await syncA.syncNow();
    await syncB.syncNow();
    expect(repoB.memories.single.title, 'Primer viaje juntos');
    expect(repoB.memories.single.media.where((x) => !x.isVideo), isEmpty);
    expect(repoB.fileFor(photoItem).existsSync(), isFalse);

    // Beto borra la cita; Ana deja de verla.
    await repoB.deleteAppointment(cita.id);
    await syncB.syncNow();
    await syncA.syncNow();
    expect(repoA.appointments, isEmpty);

    // El buzón queda vacío: nada se queda guardado en el servidor.
    expect(server.rows, isEmpty);
    expect(server.blobs, isEmpty);
    expect(syncA.pending, 0);
    expect(syncB.pending, 0);
  });

  test('gana el cambio más reciente', () async {
    final server = FakeServer();
    final (repoA, syncA) = await device(server, 'Ana', root);
    final (repoB, syncB) = await device(server, 'Beto', root);
    final invite = await syncA.createInvite();
    await syncB.joinWithInvite(invite.code.value);

    final cita = Appointment(
      id: newId(),
      title: 'v1',
      start: DateTime(2026, 5, 1),
      updatedAt: 0,
    );
    await repoA.saveAppointment(cita);
    await syncA.syncNow();
    await syncB.syncNow();

    // Un cambio viejo que llega tarde no pisa uno más nuevo.
    await repoB.applyRecord('appointment', {
      ...Appointment(
        id: cita.id,
        title: 'viejo',
        start: cita.start,
        updatedAt: 1,
      ).toRow(),
    });
    await repoB.load();
    expect(repoB.appointments.single.title, 'v1');
  });

  test('código temporal: mal escrito, inexistente o ya usado', () async {
    final server = FakeServer();
    final (_, syncA) = await device(server, 'Ana', root);
    final (_, syncB) = await device(server, 'Beto', root);
    final (_, syncC) = await device(server, 'Caro', root);

    expect(() => syncB.joinWithInvite('ABC'), throwsFormatException);
    await expectLater(
      syncB.joinWithInvite('K7M-2QX-9TB'),
      throwsFormatException,
    );

    final invite = await syncA.createInvite();
    expect(InviteCode.tryParse(invite.code.display)!.value, invite.code.value);
    await syncB.joinWithInvite(invite.code.display);
    // Ya se usó: nadie más puede entrar con él.
    await expectLater(
      syncC.joinWithInvite(invite.code.display),
      throwsFormatException,
    );
    expect(syncC.paired, isFalse);

    // Invitar de nuevo reutiliza el mismo buzón.
    final again = await syncA.createInvite();
    await syncC.joinWithInvite(again.code.display);
    expect(syncC.pairCode, syncA.pairCode);
  });

  test('máximo 3 favoritos, y se comparten', () async {
    final server = FakeServer();
    final (repoA, syncA) = await device(server, 'Ana', root);
    final (repoB, syncB) = await device(server, 'Beto', root);
    for (var i = 0; i < 4; i++) {
      await repoA.saveMemory(
        Memory(
          id: 'm$i',
          title: 'R$i',
          date: DateTime(2026, 1, i + 1),
          updatedAt: 0,
        ),
      );
    }
    expect(await repoA.toggleFavorite('m0'), isTrue);
    expect(await repoA.toggleFavorite('m1'), isTrue);
    expect(await repoA.toggleFavorite('m2'), isTrue);
    expect(await repoA.toggleFavorite('m3'), isFalse);
    expect(repoA.favorites.map((m) => m.id), ['m0', 'm1', 'm2']);
    expect(await repoA.toggleFavorite('m1'), isTrue); // quitar
    expect(await repoA.toggleFavorite('m3'), isTrue);
    expect(repoA.favorites.map((m) => m.id), ['m0', 'm2', 'm3']);

    final invite = await syncA.createInvite();
    await syncB.joinWithInvite(invite.code.value);
    expect(repoB.favorites.map((m) => m.id), ['m0', 'm2', 'm3']);
  });

  test('la fecha de mes y aniversario se comparte', () async {
    final server = FakeServer();
    final (repoA, syncA) = await device(server, 'Ana', root);
    final (repoB, syncB) = await device(server, 'Beto', root);
    await repoA.setAnniversary(DateTime(2025, 8, 31));
    final invite = await syncA.createInvite();
    await syncB.joinWithInvite(invite.code.value);
    expect(repoB.anniversary, DateTime(2025, 8, 31));

    await repoB.setAnniversary(DateTime(2025, 8, 30));
    await syncB.syncNow();
    await syncA.syncNow();
    expect(repoA.anniversary, DateTime(2025, 8, 30));
  });

  test(
    'quien crea el código sabe que la pareja se conectó aunque ella no tenga nada',
    () async {
      final server = FakeServer();
      final (_, syncA) = await device(server, 'Ana', root);
      final (repoB, syncB) = await device(server, 'Beto', root);

      final invite = await syncA.createInvite();
      await syncB.joinWithInvite(invite.code.display);
      expect(syncA.partnerName, isNull);

      await syncA.syncNow();
      expect(syncA.partnerName, 'Beto');

      // Si cambia su nombre, a la pareja le llega.
      await repoB.setMyName('Beto Pérez');
      await syncB.syncNow();
      await syncA.syncNow();
      expect(syncA.partnerName, 'Beto Pérez');
    },
  );

  group('mensajes que no se pueden leer', () {
    /// Deja un mensaje en el buzón como si lo hubiera enviado [sender].
    void inject(
      FakeServer server,
      String couple,
      String sender,
      String kind,
      String payload, {
      String? path,
    }) {
      final id = server.nextId();
      server.rows.add((
        id: id,
        couple: couple,
        sender: sender,
        msg: MailboxMessage(
          id: id,
          kind: kind,
          payload: payload,
          objectPath: path,
        ),
      ));
    }

    test('no bloquean el buzón: se descartan y llega lo siguiente', () async {
      final server = FakeServer();
      final (repoA, syncA) = await device(server, 'Ana', root);
      final (repoB, syncB) = await device(server, 'Beto', root);
      final invite = await syncA.createInvite();
      await syncB.joinWithInvite(invite.code.display);
      await syncA.syncNow();

      final crypto = await CoupleCrypto.fromSecret(
        PairSecret.tryParse(syncA.pairCode!)!,
      );
      final couple = crypto.coupleId;
      Future<String> enc(Object json) => crypto.encryptText(jsonEncode(json));

      inject(server, couple, 'Ana', 'record', 'esto no está cifrado');
      inject(server, couple, 'Ana', 'record', base64.encode([1, 2, 3]));
      inject(server, couple, 'Ana', 'record', await enc([1, 2]));
      inject(
        server,
        couple,
        'Ana',
        'record',
        await enc({
          'type': 'memory',
          'data': {'title': 5},
        }),
      );
      inject(server, couple, 'Ana', 'record', await enc({'type': 'memory'}));
      inject(
        server,
        couple,
        'Ana',
        'file',
        await enc({'mediaId': newId(), 'ext': 'jpg'}),
        path: '$couple/no-existe',
      );
      server.blobs['$couple/peligroso'] = await crypto.encrypt([1, 2, 3]);
      inject(
        server,
        couple,
        'Ana',
        'file',
        await enc({'mediaId': '../../fuera', 'ext': 'db'}),
        path: '$couple/peligroso',
      );

      // Después de todo eso, Ana guarda un recuerdo normal.
      await repoA.saveMemory(
        Memory(
          id: newId(),
          title: 'Llegó igual',
          date: DateTime(2026, 6, 1),
          updatedAt: 0,
        ),
      );
      await syncA.syncNow();
      await syncB.syncNow();

      expect(syncB.lastError, isNull);
      expect(repoB.memories.map((m) => m.title), ['Llegó igual']);
      expect(server.rows, isEmpty, reason: 'todo se confirmó');
      expect(File(p.join(root.path, 'Beto', 'fuera.db')).existsSync(), isFalse);
    });

    test(
      'si falla la red al descargar, el mensaje espera al próximo intento',
      () async {
        final server = FakeServer();
        final (repoA, syncA) = await device(server, 'Ana', root);
        final (repoB, syncB) = await device(server, 'Beto', root);
        final photo = File(p.join(root.path, 'foto.jpg'))
          ..writeAsBytesSync([4, 5, 6]);
        await repoA.saveMemory(
          Memory(
            id: newId(),
            title: 'Con foto',
            date: DateTime(2026, 7, 1),
            updatedAt: 0,
          ),
          added: [PickedMedia(photo.path, isVideo: false)],
        );
        final invite = await syncA.createInvite();

        server.failDownloadsFor = 'Beto';
        await syncB.joinWithInvite(invite.code.display);
        expect(syncB.lastError, isNotNull);
        expect(
          server.rows.where((r) => r.msg.kind == 'file'),
          hasLength(1),
          reason: 'el archivo sigue esperando en el buzón',
        );

        server.failDownloadsFor = null;
        await syncB.syncNow();
        expect(syncB.lastError, isNull);
        final item = repoB.memories.single.media.single;
        expect(repoB.fileFor(item).readAsBytesSync(), [4, 5, 6]);
        // Lo que Ana envió ya se recibió (el saludo de Beto espera a Ana).
        expect(server.rows.where((r) => r.sender == 'Ana'), isEmpty);
      },
    );
  });

  test('el nombre de la pareja se limpia y se recorta', () {
    expect(cleanPartnerName(null), isNull);
    expect(cleanPartnerName(42), isNull);
    expect(cleanPartnerName('   '), isNull);
    expect(cleanPartnerName('  Ana\n '), 'Ana');
    expect(cleanPartnerName('A\u0000na'), 'Ana');
    final long = cleanPartnerName('😀' * 100)!;
    expect(long.runes.length, maxNameLength);
  });
}
