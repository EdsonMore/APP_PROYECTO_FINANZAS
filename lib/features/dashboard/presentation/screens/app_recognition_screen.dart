import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/account.dart';
import 'package:saldo_claro/core/notification/notification_listener_channel.dart';
import 'package:saldo_claro/core/permissions/notification_permission_service.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/icon_catalog.dart';

/// Pantalla de Reconocimiento de Apps:
/// permite mapear nuevos packages de apps (Interbank, BBVA, Plin, etc.)
/// a una cuenta usando la captura de una notificación de prueba.
class AppRecognitionScreen extends ConsumerStatefulWidget {
  const AppRecognitionScreen({super.key});

  @override
  ConsumerState<AppRecognitionScreen> createState() =>
      _AppRecognitionScreenState();
}

class _AppRecognitionScreenState extends ConsumerState<AppRecognitionScreen> {
  bool _listening = false;
  List<Account> _accounts = [];
  List<AccountSourceMapping> _sources = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accountRepo = ref.read(accountRepositoryProvider);
    _accounts = await accountRepo.fetchAll();
    _sources = await accountRepo.fetchSources();
    if (mounted) setState(() {});
  }

  Future<void> _startCapture() async {
    setState(() => _listening = true);
    final channel = NotificationListenerChannel.instance;
    final permissions = NotificationPermissionService.instance;

    // 1) Re-enlaza el listener con el sistema (por si quedó desvinculado).
    await permissions.requestRebind();

    // 2) Activa el modo "capturar TODO": mientras dure el mapeo, el listener
    //    nativo reenvía notificaciones de CUALQUIER app (no solo de la lista
    //    base), para poder descubrir el package de apps como Sip.
    await permissions.setCaptureAll(true);

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Escuchando… Envía una notificación de prueba desde la app que '
              'quieras mapear (ej. un pago de S/1).',
            ),
            duration: Duration(seconds: 8),
          ),
        );
      }

      final raw = await channel
          .listen()
          .first
          .timeout(
            const Duration(seconds: 90),
            onTimeout: () => throw TimeoutException('Sin notificaciones en 90s'),
          );
      final account = await _pickAccount(
        packageName: raw.packageName,
        appName: raw.title,
      );
      if (account != null) {
        await ref.read(accountRepositoryProvider).upsertSource(
              accountId: account.id,
              packageName: raw.packageName,
              appName: account.name,
            );
        // 3) Registra el package en el listener nativo para que siga
        //    capturándolo automáticamente en el futuro.
        await permissions.addAllowedPackage(raw.packageName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${raw.packageName} mapeado a "${account.name}".'),
            ),
          );
        }
        await _load();
      }
    } catch (_) {
      // No se capturó ninguna notificación a tiempo.
    } finally {
      // 4) Apaga el modo captura-total: la app vuelve a leer solo las apps
      //    financieras conocidas o mapeadas (privacidad por defecto).
      await permissions.setCaptureAll(false);
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<Account?> _pickAccount({
    required String packageName,
    required String appName,
  }) {
    return showDialog<Account>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Asignar a una cuenta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Package detectado: $packageName'),
            Text('App: $appName'),
            const SizedBox(height: 12),
            const Text('¿A qué cuenta pertenece?'),
            const SizedBox(height: 12),
            for (final account in _accounts)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(account.resolvedColor),
                  child: Icon(IconCatalog.iconFor(account.resolvedIcon),
                      size: 16, color: Colors.white),
                ),
                title: Text(account.name),
                onTap: () => Navigator.pop(ctx, account),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSource(AccountSourceMapping source) async {
    await ref.read(accountRepositoryProvider).deleteSource(source.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reconocimiento de apps')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Nueva app? ¡Mapeala!',
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Captura una notificación de prueba desde la app que quieras '
                    'reconocer (ej. Interbank, BBVA, Plin) y asígnala a una de tus '
                    'cuentas. A partir de ahí se clasificará automáticamente.',
                    style: TextStyle(
                        color: Color(ColorConfig.textSecondary), height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _listening ? null : _startCapture,
                    icon: const Icon(Icons.notifications_active),
                    label: Text(_listening
                        ? 'Escuchando…'
                        : 'Capturar notificación de prueba'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Apps ya mapeadas',
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_sources.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No hay apps mapeadas todavía.',
                style: TextStyle(color: Color(ColorConfig.textSecondary)),
              ),
            )
          else
            for (final source in _sources) _sourceTile(source),
          const SizedBox(height: 24),
          Text(
            'Sugerencias',
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kKnownAppPackages.entries)
                Chip(label: Text('${entry.key} · ${entry.value}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourceTile(AccountSourceMapping source) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.link),
        title: Text(source.appName.isEmpty ? source.packageName : source.appName),
        subtitle: Text('${source.packageName} · ${Formatters.date(source.createdAt ?? DateTime.now())}'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Color(ColorConfig.danger)),
          onPressed: () => _deleteSource(source),
        ),
      ),
    );
  }
}
