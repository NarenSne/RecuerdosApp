import 'dart:typed_data';

/// Un paquete cifrado esperando en el buzón.
class MailboxMessage {
  const MailboxMessage({
    required this.id,
    required this.kind,
    required this.payload,
    this.objectPath,
  });

  final String id;

  /// 'record' o 'file'.
  final String kind;

  /// Texto cifrado (base64). Para 'file' son los datos del archivo.
  final String payload;

  /// Dónde está guardado el archivo cifrado, solo para 'file'.
  final String? objectPath;
}

/// Error con un mensaje que se puede mostrar tal cual a la persona.
class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// El buzón temporal. Solo transporta datos cifrados; nunca los guarda de
/// forma permanente.
abstract class MailboxTransport {
  /// Inicia sesión y entra al buzón de la pareja.
  Future<void> connect(String coupleId);

  Future<void> send({
    required String coupleId,
    required String kind,
    required String payload,
    Uint8List? blob,
  });

  /// Mensajes que envió la otra persona, del más antiguo al más nuevo.
  Future<List<MailboxMessage>> fetch(String coupleId, {int limit = 20});

  /// Null si el archivo ya no existe en el buzón (o no es de este buzón):
  /// así un mensaje sin archivo no bloquea los siguientes.
  Future<Uint8List?> download(String objectPath);

  /// Borra el mensaje (y su archivo) del buzón una vez recibido.
  Future<void> ack(MailboxMessage message);

  /// Deja una invitación temporal en el servidor.
  Future<void> createInvite({
    required String lookupHash,
    required String sealedSecret,
    required Duration validFor,
  });

  /// Recoge (y borra) una invitación. Null si no existe o ya venció.
  Future<String?> claimInvite(String lookupHash);
}
