import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/auth.dart';
import '../data/milestones.dart';
import '../data/reminders.dart';
import '../data/repository.dart';
import '../sync/mailbox_transport.dart';
import '../sync/sync_service.dart';
import 'theme.dart';
import 'widgets/couple_title.dart';

class PartnerScreen extends StatelessWidget {
  const PartnerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Pareja')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _NameField(),
          const SizedBox(height: 8),
          const _NicknameTile(),
          const SizedBox(height: 8),
          const _AnniversaryCard(),
          const SizedBox(height: 16),
          if (!sync.available)
            const _NotConfiguredCard()
          else if (sync.paired)
            const _PairedCard()
          else
            const _PairCard(),
          const SizedBox(height: 24),
          const _PrivacyNote(),
          const SizedBox(height: 16),
          const _AccountSection(),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Nombre

class _NameField extends StatefulWidget {
  const _NameField();

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _c = TextEditingController(
    text: context.read<Repository>().myName,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<Repository>().setMyName(_c.text);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Nombre guardado')));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      textCapitalization: TextCapitalization.words,
      inputFormatters: [LengthLimitingTextInputFormatter(maxNameLength)],
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        labelText: 'Tu nombre',
        helperText: 'Así aparecerás en los recuerdos y citas que guardes.',
        prefixIcon: const Icon(Icons.person_outline),
        suffixIcon: TextButton(onPressed: _save, child: const Text('Guardar')),
      ),
    );
  }
}

class _NicknameTile extends StatelessWidget {
  const _NicknameTile();

  @override
  Widget build(BuildContext context) {
    final name = partnerDisplayName(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.favorite_border),
      title: const Text('Apodo de tu pareja'),
      subtitle: Text(name ?? 'Sin apodo todavía'),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => editPartnerNickname(context),
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(
            auth.providerLabel.isEmpty
                ? 'Tu cuenta'
                : 'Tu cuenta · ${auth.providerLabel}',
          ),
          subtitle: auth.accountLabel.isEmpty ? null : Text(auth.accountLabel),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('¿Cerrar sesión?'),
                  content: const Text(
                    'Tus recuerdos se quedan guardados en este teléfono. Para volver a verlos tendrás que iniciar sesión otra vez.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              );
              if (ok == true) await auth.signOut();
            },
            icon: Icon(Icons.logout, color: theme.colorScheme.error),
            label: Text(
              'Cerrar sesión',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Mes y aniversario

class _AnniversaryCard extends StatelessWidget {
  const _AnniversaryCard();

  Future<void> _pick(BuildContext context) async {
    final repo = context.read<Repository>();
    final reminders = context.read<ReminderService>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: 'El día en que empezaron',
      initialDate: repo.anniversary ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (picked == null) return;
    await repo.setAnniversary(picked);
    if (reminders.enabled) await reminders.requestPermission();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final reminders = context.watch<ReminderService>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final start = repo.anniversary;
    final today = DateTime.now();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.favorite_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Mes y aniversario', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (start == null) ...[
              const Text(
                '¿Desde cuándo están juntos? Cada mes, ese mismo día, les recordamos que cumplen mes, y cada año, el aniversario.',
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _pick(context),
                icon: const Icon(Icons.event_outlined),
                label: const Text('Elegir la fecha'),
              ),
            ] else ...[
              Text(
                'Juntos desde el ${formatDate(start)}',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 2),
              Text(
                'Llevan ${timeTogether(start, today)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final next = nextMilestone(start, today);
                  final isToday = sameDay(next.date, today);
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isToday
                          ? 'Hoy ${next.label.toLowerCase()}'
                          : 'Próximo: ${formatDayLong(next.date)} · ${next.label.toLowerCase()}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Recordármelo'),
                subtitle: Text(
                  'Cada mes y en el aniversario, a las ${ReminderService.hour}:00, en este teléfono.',
                ),
                value: reminders.enabled,
                onChanged: (v) async {
                  await reminders.setEnabled(v);
                  if (v) await reminders.requestPermission();
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _pick(context),
                  child: const Text('Cambiar fecha'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Compartir

class _NotConfiguredCard extends StatelessWidget {
  const _NotConfiguredCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compartir no está activado',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Puedes usar la app con normalidad: todo se guarda en este teléfono. Para compartir con tu pareja, esta versión necesita los datos del buzón (SUPABASE_URL y SUPABASE_ANON_KEY en lib/config.dart).',
            ),
          ],
        ),
      ),
    );
  }
}

String? _errorText(Object e) {
  switch (e) {
    case FormatException(:final message):
      return message;
    case SyncException(:final message):
      return message;
  }
  debugPrint('Pareja: $e');
  return 'Algo salió mal. Revisa tu conexión e intenta de nuevo.';
}

class _PairCard extends StatefulWidget {
  const _PairCard();

  @override
  State<_PairCard> createState() => _PairCardState();
}

class _PairCardState extends State<_PairCard> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool _needName() {
    if (context.read<Repository>().myName.isNotEmpty) return false;
    setState(() => _error = 'Primero escribe y guarda tu nombre arriba.');
    return true;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_needName()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = _errorText(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _code.text = data!.text!.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = context.read<SyncService>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Conecta con tu pareja', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Una persona crea un código y se lo envía a la otra por WhatsApp o por correo. El código sirve una sola vez y vence en 15 minutos.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(sync.createInvite),
              icon: const Icon(Icons.favorite_border),
              label: const Text('Crear código de invitación'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'o si te enviaron uno',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(letterSpacing: 2),
              decoration: InputDecoration(
                labelText: 'Código de tu pareja',
                hintText: 'K7M-2QX-9TB',
                suffixIcon: IconButton(
                  tooltip: 'Pegar',
                  icon: const Icon(Icons.content_paste),
                  onPressed: _paste,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => sync.joinWithInvite(_code.text)),
              child: const Text('Conectarme'),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Muestra el código vigente, cuánto le queda y cómo enviarlo.
class _InviteView extends StatefulWidget {
  const _InviteView({required this.invite, required this.onRenew});
  final ActiveInvite invite;
  final Future<void> Function() onRenew;

  @override
  State<_InviteView> createState() => _InviteViewState();
}

class _InviteViewState extends State<_InviteView> {
  late final Timer _tick;
  bool _renewing = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  String get _message {
    final name = context.read<Repository>().myName;
    return '${name.isEmpty ? 'Te' : '$name te'} invita a guardar sus recuerdos en Recuerditos.\n\n'
        'Abre la app, ve a Pareja → "o si te enviaron uno" y escribe este código:\n\n'
        '${widget.invite.code.display}\n\n'
        'Sirve una sola vez y vence en 15 minutos.';
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró la app. Copia el código y envíalo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = widget.invite.expiresAt.difference(DateTime.now());
    final expired = left.isNegative;

    if (expired) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'El código venció sin usarse.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _renewing
                ? null
                : () async {
                    setState(() => _renewing = true);
                    await widget.onRenew();
                    if (mounted) setState(() => _renewing = false);
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('Crear otro código'),
          ),
        ],
      );
    }

    final mm = left.inMinutes.toString();
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              SelectableText(
                widget.invite.code.display,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Vence en $mm:$ss',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _open(
            Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_message)}'),
          ),
          icon: const Icon(Icons.chat_outlined),
          label: const Text('Enviar por WhatsApp'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _open(
                  Uri.parse(
                    'mailto:?subject=${Uri.encodeComponent('Tu código para Recuerditos')}'
                    '&body=${Uri.encodeComponent(_message)}',
                  ),
                ),
                icon: const Icon(Icons.mail_outline),
                label: const Text('Por correo'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: widget.invite.code.display),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Código copiado')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PairedCard extends StatefulWidget {
  const _PairedCard();

  @override
  State<_PairedCard> createState() => _PairedCardState();
}

class _PairedCardState extends State<_PairedCard> {
  bool _creating = false;
  String? _inviteError;

  Future<void> _newInvite() async {
    setState(() {
      _creating = true;
      _inviteError = null;
    });
    try {
      await context.read<SyncService>().createInvite();
    } catch (e) {
      _inviteError = _errorText(e);
    }
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _unpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Dejar de compartir?'),
        content: const Text(
          'Tus recuerdos y citas se quedan en este teléfono. Lo nuevo ya no se enviará a tu pareja ni recibirás lo suyo. Para volver a conectarse necesitarán un código nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dejar de compartir'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<SyncService>().unpair();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final invite = sync.activeInvite;
    final waiting = sync.partnerName == null;

    final String status;
    if (sync.syncing) {
      status = sync.pending > 0
          ? 'Enviando… faltan ${sync.pending}'
          : 'Sincronizando…';
    } else if (sync.pending > 0) {
      status = sync.pending == 1
          ? '1 cambio por enviar'
          : '${sync.pending} cambios por enviar';
    } else if (sync.lastSync != null) {
      final t = sync.lastSync!;
      status = sameDay(t, DateTime.now())
          ? 'Al día · hoy a las ${formatTime(t)}'
          : 'Al día · ${formatDate(t)}';
    } else {
      status = 'Todavía no se ha sincronizado';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              waiting
                  ? 'Esperando a tu pareja'
                  : 'Compartiendo con ${sync.partnerName}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              waiting
                  ? 'Envíale el código. Lo que ya guardaste le llegará apenas se conecte.'
                  : status,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            if (invite != null || waiting) ...[
              const SizedBox(height: 16),
              if (invite != null)
                _InviteView(invite: invite, onRenew: _newInvite)
              else
                FilledButton.icon(
                  onPressed: _creating ? null : _newInvite,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Crear otro código'),
                ),
            ],
            if (_inviteError != null) ...[
              const SizedBox(height: 12),
              Text(
                _inviteError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (sync.lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                sync.lastError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (sync.skippedTooBig > 0) ...[
              const SizedBox(height: 12),
              Text(
                '${sync.skippedTooBig} video(s) pesan más de 45 MB y se quedaron solo en este teléfono.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: sync.syncing ? null : sync.syncNow,
              icon: sync.syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: const Text('Sincronizar ahora'),
            ),
            if (!waiting && invite == null)
              TextButton(
                onPressed: _creating ? null : _newInvite,
                child: const Text('Invitar de nuevo (cambio de teléfono)'),
              ),
            TextButton(
              onPressed: _unpair,
              child: const Text('Dejar de compartir'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, size: 20, color: muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Tus recuerdos viven en este teléfono, no en la nube. Para llegar a tu pareja viajan cifrados por un buzón temporal que los borra en cuanto los recibe. Si desinstalas la app, se borran de este teléfono.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}
