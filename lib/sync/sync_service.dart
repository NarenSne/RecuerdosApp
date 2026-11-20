import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../data/repository.dart';
import 'couple_crypto.dart';
import 'mailbox_transport.dart';

/// Envía los cambios de este teléfono al buzón y aplica los que dejó la
/// pareja. Los mensajes recibidos se borran del buzón enseguida.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.repo,
    required this.transport,
    this.maxShareBytes = AppConfig.maxShareBytes,
  });

  final Repository repo;
  final MailboxTransport? transport;
  final int maxShareBytes;

  CoupleCrypto? _crypto;
  String? _code;
  bool _connected = false;
  bool _syncing = false;
  bool _again = false;
  Timer? _debounce;

  String? lastError;
  DateTime? lastSync;
  String? partnerName;
  int pending = 0;

  /// Videos que no se enviaron por superar el tamaño máximo.
  int skippedTooBig = 0;

  /// Hay un buzón configurado en esta versión de la app.
  bool get available => transport != null;
  bool get paired => _crypto != null;
  bool get syncing => _syncing;

  /// El secreto del buzón. Solo para comprobar en pruebas que dos teléfonos
  /// comparten el mismo; nunca se muestra.
  @visibleForTesting
  String? get pairCode => _code;

  Future<void> init() async {
    _code = await repo.getSetting('pair_code');
    partnerName = await repo.getSetting('partner_name');
    final ls = await repo.getSetting('last_sync');
    if (ls != null) {
      lastSync = DateTime.fromMillisecondsSinceEpoch(int.parse(ls));
    }
    final secret = _code == null ? null : PairSecret.tryParse(_code!);
    if (secret != null) _crypto = await CoupleCrypto.fromSecret(secret);
    pending = await repo.outboxCount();
    repo.onLocalChange = scheduleSync;
    notifyListeners();
  }

  /// La última invitación creada en este teléfono, si sigue vigente.
  ActiveInvite? get activeInvite {
    final i = _invite;
    return i != null && i.expiresAt.isAfter(DateTime.now()) ? i : null;
  }

  ActiveInvite? _invite;

  /// Crea un código temporal para la pareja. Si aún no hay buzón, lo crea;
  /// si ya existe (por ejemplo, tu pareja cambió de teléfono), invita al mismo.
  Future<ActiveInvite> createInvite() async {
    final t = transport;
    if (t == null) throw const SyncException('Compartir no está activado.');
    final existing = _code == null ? null : PairSecret.tryParse(_code!);
    final secret = existing ?? PairSecret.generate();
    final code = InviteCode.generate();
    await t.createInvite(
      lookupHash: await code.lookupHash(),
      sealedSecret: await code.seal(secret),
      validFor: InviteCode.validFor,
    );
    final invite = ActiveInvite(code, DateTime.now().add(InviteCode.validFor));
    _invite = invite;
    if (existing == null) {
      await _pairWith(secret);
    } else {
      notifyListeners();
    }
    return invite;
  }

  /// Se une al buzón de la pareja con el código temporal que te envió.
  Future<void> joinWithInvite(String input) async {
    final t = transport;
    if (t == null) throw const SyncException('Compartir no está activado.');
    final code = InviteCode.tryParse(input);
    if (code == null) {
      throw const FormatException(
        'El código tiene 9 letras y números, por ejemplo K7M-2QX-9TB.',
      );
    }
    final sealed = await t.claimInvite(await code.lookupHash());
    final secret = sealed == null ? null : await code.open(sealed);
    if (secret == null) {
      throw const FormatException(
        'Ese código no existe o ya venció. Pídele a tu pareja uno nuevo.',
      );
    }
    _invite = null;
    await _pairWith(secret);
  }

  Future<void> _pairWith(PairSecret secret) async {
    _crypto = await CoupleCrypto.fromSecret(secret);
    _code = secret.encode();
    _connected = false;
    await repo.setSetting('pair_code', _code);
    // Lo que ya estaba guardado también se comparte.
    await repo.enqueueEverything();
    pending = await repo.outboxCount();
    notifyListeners();
    await syncNow();
  }

  Future<void> unpair() async {
    _debounce?.cancel();
    _crypto = null;
    _code = null;
    _invite = null;
    _connected = false;
    partnerName = null;
    lastError = null;
    await repo.setSetting('pair_code', null);
    await repo.setSetting('partner_name', null);
    await repo.clearOutbox();
    pending = 0;
    notifyListeners();
  }

  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
    repo.outboxCount().then((n) {
      pending = n;
      notifyListeners();
    });
  }

  Future<void> syncNow() async {
    final t = transport;
    if (t == null || _crypto == null) return;
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    lastError = null;
    notifyListeners();
    try {
      do {
        _again = false;
        if (!_connected) {
          await t.connect(_crypto!.coupleId);
          _connected = true;
        }
        await _push(t);
        await _pull(t);
      } while (_again && _crypto != null);
      lastSync = DateTime.now();
      await repo.setSetting('last_sync', '${lastSync!.millisecondsSinceEpoch}');
    } on SyncException catch (e) {
      lastError = e.message;
    } on SocketException {
      lastError =
          'Sin conexión a internet. Se enviará cuando vuelvas a tener señal.';
    } catch (e) {
      debugPrint('Sincronización: $e');
      lastError = 'No se pudo sincronizar. Se intentará de nuevo.';
    } finally {
      _syncing = false;
      pending = await repo.outboxCount();
      notifyListeners();
    }
  }

  Future<void> _push(MailboxTransport t) async {
    while (true) {
      final crypto = _crypto;
      if (crypto == null) return;
      final batch = await repo.pendingOutbox();
      if (batch.isEmpty) return;
      for (final e in batch) {
        if (e.kind == 'record') {
          final data = await repo.exportRecord(e.refType, e.refId);
          if (data != null) {
            final payload = await crypto.encryptText(
              jsonEncode({
                'v': 1,
                'type': e.refType,
                'from': repo.myName,
                'data': data,
              }),
            );
            await t.send(
              coupleId: crypto.coupleId,
              kind: 'record',
              payload: payload,
            );
          }
        } else if (e.kind == 'file') {
          await _pushFile(t, crypto, e.refId);
        }
        await repo.removeOutbox(e.id);
        pending = await repo.outboxCount();
        notifyListeners();
      }
    }
  }

  Future<void> _pushFile(
    MailboxTransport t,
    CoupleCrypto crypto,
    String mediaId,
  ) async {
    final media = await repo.mediaById(mediaId);
    if (media == null || media.deleted) return;
    final file = repo.fileFor(media);
    if (!await file.exists()) return;
    if (await file.length() > maxShareBytes) {
      skippedTooBig++;
      return;
    }
    final blob = await crypto.encrypt(await file.readAsBytes());
    final payload = await crypto.encryptText(
      jsonEncode({
        'v': 1,
        'mediaId': media.id,
        'ext': media.ext,
        'memoryId': media.memoryId,
      }),
    );
    await t.send(
      coupleId: crypto.coupleId,
      kind: 'file',
      payload: payload,
      blob: blob,
    );
  }

  Future<void> _pull(MailboxTransport t) async {
    for (var page = 0; page < 50; page++) {
      final crypto = _crypto;
      if (crypto == null) return;
      final messages = await t.fetch(crypto.coupleId);
      if (messages.isEmpty) return;
      for (final m in messages) {
        await _receive(t, crypto, m);
        await t.ack(m);
      }
      await repo.load();
    }
  }

  /// Procesa un mensaje. Si no se puede leer (no es de la pareja, llegó dañado
  /// o tiene datos inválidos) se descarta: después se confirma igual para que
  /// no bloquee los siguientes. Los errores de red sí se propagan, y el
  /// mensaje se queda en el buzón para el próximo intento.
  Future<void> _receive(
    MailboxTransport t,
    CoupleCrypto crypto,
    MailboxMessage m,
  ) async {
    final env = await _openEnvelope(crypto, m.payload);
    if (env == null) {
      debugPrint('Mensaje del buzón descartado: no se pudo abrir');
      return;
    }
    try {
      if (m.kind == 'record') {
        await _receiveRecord(env);
      } else if (m.kind == 'file' && m.objectPath != null) {
        await _receiveFile(t, crypto, m.objectPath!, env);
      }
    } on FormatException catch (e) {
      debugPrint('Mensaje del buzón descartado: ${e.message}');
    }
  }

  Future<Map<String, dynamic>?> _openEnvelope(
    CoupleCrypto crypto,
    String payload,
  ) async {
    try {
      final decoded = jsonDecode(await crypto.decryptText(payload));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on SecretBoxAuthenticationError {
      return null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null; // Demasiado corto para ser un mensaje cifrado.
    }
  }

  Future<void> _receiveRecord(Map<String, dynamic> env) async {
    final type = env['type'];
    final data = env['data'];
    if (type is! String || data is! Map) {
      throw const FormatException('Mensaje sin tipo o sin datos');
    }
    await repo.applyRecord(type, Map<String, dynamic>.from(data));
    final from = cleanPartnerName(env['from']);
    if (from != null && from != partnerName) {
      partnerName = from;
      await repo.setSetting('partner_name', from);
    }
  }

  Future<void> _receiveFile(
    MailboxTransport t,
    CoupleCrypto crypto,
    String objectPath,
    Map<String, dynamic> env,
  ) async {
    final mediaId = env['mediaId'];
    final ext = env['ext'];
    if (mediaId is! String || ext is! String) {
      throw const FormatException('Archivo sin nombre');
    }
    final encrypted = await t.download(objectPath);
    if (encrypted == null) {
      throw const FormatException('El archivo ya no está en el buzón');
    }
    final List<int> bytes;
    try {
      bytes = await crypto.decrypt(encrypted);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Archivo dañado o de otro buzón');
    } on ArgumentError {
      throw const FormatException('Archivo dañado');
    }
    await repo.storeIncomingFile(mediaId, ext, bytes);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// Nombre que llega de la pareja, limpio y de un largo razonable para
/// mostrarlo. Null si no hay nombre.
String? cleanPartnerName(Object? raw) {
  if (raw is! String) return null;
  final name = raw.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '').trim();
  if (name.isEmpty) return null;
  final runes = name.runes;
  return runes.length <= maxNameLength
      ? name
      : String.fromCharCodes(runes.take(maxNameLength)).trim();
}

class ActiveInvite {
  const ActiveInvite(this.code, this.expiresAt);
  final InviteCode code;
  final DateTime expiresAt;
}
