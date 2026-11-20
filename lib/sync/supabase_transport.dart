import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'mailbox_transport.dart';

/// Buzón sobre Supabase: una tabla `mailbox` y un bucket privado `mailbox`.
/// Ver supabase/schema.sql.
class SupabaseTransport implements MailboxTransport {
  SupabaseClient get _c => Supabase.instance.client;
  static const _bucket = 'mailbox';
  static const _uuid = Uuid();

  /// El buzón usa la cuenta con la que la persona inició sesión.
  Future<void> _ensureSession() async {
    if (_c.auth.currentUser == null) {
      throw const SyncException('Inicia sesión para compartir con tu pareja.');
    }
  }

  @override
  Future<void> connect(String coupleId) => _guard(() async {
    await _ensureSession();
    await _c.rpc('join_couple', params: {'p_couple': coupleId});
  });

  @override
  Future<void> createInvite({
    required String lookupHash,
    required String sealedSecret,
    required Duration validFor,
  }) => _guard(() async {
    await _ensureSession();
    await _c.rpc(
      'create_invite',
      params: {
        'p_code_hash': lookupHash,
        'p_payload': sealedSecret,
        'p_minutes': validFor.inMinutes,
      },
    );
  });

  @override
  Future<String?> claimInvite(String lookupHash) => _guard(() async {
    await _ensureSession();
    final result = await _c.rpc(
      'claim_invite',
      params: {'p_code_hash': lookupHash},
    );
    return result is String ? result : null;
  });

  @override
  Future<void> send({
    required String coupleId,
    required String kind,
    required String payload,
    Uint8List? blob,
  }) => _guard(() async {
    String? path;
    if (blob != null) {
      path = '$coupleId/${_uuid.v4()}';
      await _c.storage
          .from(_bucket)
          .uploadBinary(
            path,
            blob,
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
            ),
          );
    }
    await _c.from('mailbox').insert({
      'couple_id': coupleId,
      'kind': kind,
      'payload': payload,
      'object_path': path,
    });
  });

  @override
  Future<List<MailboxMessage>> fetch(String coupleId, {int limit = 20}) =>
      _guard(() async {
        final rows = await _c
            .from('mailbox')
            .select('id, kind, payload, object_path')
            .eq('couple_id', coupleId)
            .order('created_at', ascending: true)
            .limit(limit);
        return [
          for (final r in rows)
            MailboxMessage(
              id: r['id'] as String,
              kind: r['kind'] as String,
              payload: r['payload'] as String,
              objectPath: r['object_path'] as String?,
            ),
        ];
      });

  @override
  Future<Uint8List?> download(String objectPath) => _guard(() async {
    try {
      return await _c.storage.from(_bucket).download(objectPath);
    } on StorageException catch (e) {
      // Supabase responde 404 tanto si no existe como si no es de este
      // buzón: en ambos casos nunca se podrá descargar.
      if (e.statusCode == '404') return null;
      rethrow;
    }
  });

  @override
  Future<void> ack(MailboxMessage message) => _guard(() async {
    if (message.objectPath != null) {
      await _c.storage.from(_bucket).remove([message.objectPath!]);
    }
    await _c.from('mailbox').delete().eq('id', message.id);
  });

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on SocketException {
      throw const SyncException(
        'Sin conexión a internet. Se enviará cuando vuelvas a tener señal.',
      );
    } on AuthException catch (e) {
      debugPrint('Buzón (sesión): ${e.message}');
      throw const SyncException(
        'Tu sesión venció. Cierra sesión y vuelve a entrar.',
      );
    } on PostgrestException catch (e) {
      debugPrint('Buzón: ${e.code} ${e.message}');
      if (e.code == 'PGRST202' || e.code == '42P01' || e.code == 'PGRST205') {
        throw const SyncException(
          'El buzón no está preparado. Ejecuta supabase/schema.sql en tu '
          'proyecto de Supabase.',
        );
      }
      // P0001: mensajes propios de supabase/schema.sql, escritos para mostrar.
      if (e.code == 'P0001') throw SyncException(e.message);
      if (e.code == '42501') {
        throw const SyncException(
          'El buzón no aceptó tu cuenta. Cierra sesión y entra con Google.',
        );
      }
      throw const SyncException(
        'El buzón no respondió bien. Se intentará de nuevo en un momento.',
      );
    } on StorageException catch (e) {
      debugPrint('Buzón (archivo): ${e.statusCode} ${e.message}');
      if (e.statusCode == '413') {
        throw const SyncException(
          'Un archivo es demasiado grande para el buzón.',
        );
      }
      throw const SyncException(
        'No se pudo transferir un archivo. Se intentará de nuevo.',
      );
    }
  }
}
