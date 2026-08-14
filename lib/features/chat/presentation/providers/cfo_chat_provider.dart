import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/core/providers/service_providers.dart';
import 'package:saldo_claro/core/services/cfo_chat_service.dart';
import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';

/// Estado del chat: mensajes del hilo + flag de carga.
class CfoChatState {
  const CfoChatState({
    this.messages = const [],
    this.loading = false,
  });

  final List<ChatTurn> messages;
  final bool loading;

  CfoChatState copyWith({List<ChatTurn>? messages, bool? loading}) {
    return CfoChatState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
    );
  }
}

/// Controlador del ChatFinanciero "CFO de bolsillo".
///
/// Construye el contexto (JSON) con los datos del usuario y lo envía a la IA
/// (Gemini -> Groq -> resumen local) junto con la pregunta y el historial.
class CfoChatController extends Notifier<CfoChatState> {
  CfoChatService? _service;
  bool _disposed = false;

  @override
  CfoChatState build() {
    _disposed = false;
    _service = CfoChatService(ai: ref.watch(aiServiceProvider));
    ref.onDispose(() => _disposed = true);
    return const CfoChatState();
  }

  bool get aiAvailable => _service?.available ?? false;

  Future<void> send(String text) async {
    final service = _service;
    final message = text.trim();
    if (service == null || message.isEmpty || state.loading) return;

    state = state.copyWith(
      messages: [...state.messages, ChatTurn(role: 'user', text: message)],
      loading: true,
    );

    try {
      final transactions =
          ref.read(allTransactionsProvider).value ?? const [];
      final accounts = ref.read(accountsProvider).value ?? const [];

      final contextJson = service.buildContextJson(
        transactions: transactions,
        accounts: accounts,
      );

      final history =
          state.messages.sublist(0, state.messages.length - 1);
      final reply = await service.ask(
        question: message,
        contextJson: contextJson,
        history: history,
      );

      if (_disposed) return;
      state = state.copyWith(
        messages: [...state.messages, ChatTurn(role: 'assistant', text: reply)],
        loading: false,
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        messages: [
          ...state.messages,
          const ChatTurn(
            role: 'assistant',
            text: '😅 Ocurrió un error al consultar al CFO. Inténtalo de nuevo.',
          ),
        ],
        loading: false,
      );
    }
  }

  void clear() {
    state = const CfoChatState();
  }
}

final cfoChatProvider =
    NotifierProvider<CfoChatController, CfoChatState>(CfoChatController.new);