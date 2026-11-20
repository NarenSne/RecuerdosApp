import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../sync/sync_service.dart';
import '../theme.dart';

/// Cómo se llama a la pareja en la app: el apodo, o su nombre si ya se
/// conectaron, o null si todavía no hay ninguno.
String? partnerDisplayName(BuildContext context) {
  final nickname = context.watch<Repository>().partnerNickname;
  if (nickname.isNotEmpty) return nickname;
  final name = context.watch<SyncService>().partnerName;
  return name == null || name.isEmpty ? null : name;
}

/// Diálogo para ponerle (o cambiarle) el apodo a la pareja.
Future<void> editPartnerNickname(BuildContext context) async {
  final repo = context.read<Repository>();
  final suggested = repo.partnerNickname.isNotEmpty
      ? repo.partnerNickname
      : (context.read<SyncService>().partnerName ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _NicknameDialog(initial: suggested),
  );
  if (result != null) await repo.setPartnerNickname(result);
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial});
  final String initial;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  // El diálogo es dueño del controlador: se libera cuando termina de cerrarse.
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Cómo le dices a tu pareja?'),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        inputFormatters: [LengthLimitingTextInputFormatter(maxNameLength)],
        onSubmitted: (v) => Navigator.pop(context, v),
        decoration: const InputDecoration(
          labelText: 'Nombre o apodo',
          hintText: 'Ej. Mi amor, Gordi, Sol',
          helperText: 'Solo se ve en tu teléfono.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _c.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Encabezado de Recuerdos: "RECUERDOS con:" y el nombre de la pareja.
class CoupleTitle extends StatelessWidget {
  const CoupleTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = partnerDisplayName(context);
    return Semantics(
      button: true,
      label: name == null
          ? 'Recuerdos. Ponerle un apodo a tu pareja'
          : 'Recuerdos con $name. Cambiar apodo',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => editPartnerNickname(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RECUERDOS con:',
                style: TextStyle(
                  fontFamily: titleFont,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  letterSpacing: 2.2,
                  color: scheme.primary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      name ?? 'ponle un apodo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: scriptFont,
                        fontWeight: FontWeight.w600,
                        fontSize: name == null ? 28 : 36,
                        height: 1.15,
                        color: name == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    name == null ? Icons.add : Icons.edit_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
