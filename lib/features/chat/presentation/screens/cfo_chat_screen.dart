import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/services/cfo_chat_service.dart';
import 'package:saldo_claro/features/chat/presentation/providers/cfo_chat_provider.dart';

/// Pantalla de chat interactivo "CFO de bolsillo" (Gemini).
class CfoChatScreen extends ConsumerStatefulWidget {
  const CfoChatScreen({super.key});

  @override
  ConsumerState<CfoChatScreen> createState() => _CfoChatScreenState();
}

class _CfoChatScreenState extends ConsumerState<CfoChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    _controller.clear();
    ref.read(cfoChatProvider.notifier).send(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(cfoChatProvider);
    final aiAvailable = ref.read(cfoChatProvider.notifier).aiAvailable;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CFO de bolsillo 🤖'),
        actions: [
          if (chatState.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Limpiar chat',
              onPressed: () {
                ref.read(cfoChatProvider.notifier).clear();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (!aiAvailable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFF39C12).withValues(alpha: 0.15),
              child: const Text(
                '⚠️ IA no configurada. Agrega tu clave de Gemini o Groq para '
                'activar el CFO de bolsillo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFF39C12),
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: chatState.messages.length +
                  (chatState.messages.isEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (chatState.messages.isEmpty) {
                  return _Greeting(onAsk: _send);
                }
                final message = chatState.messages[index];
                final isLast = index == chatState.messages.length - 1;
                if (isLast && chatState.loading) {
                  _scrollToBottom();
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                _scrollToBottom();
                return _MessageBubble(message: message);
              },
            ),
          ),
          _QuickSuggestions(onAsk: _send),
          _InputBar(controller: _controller, onSend: _send),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.onAsk});

  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome, size: 48, color: Color(0xFFF39C12)),
          const SizedBox(height: 16),
          Text(
            'Hola, soy tu CFO de bolsillo 💼\nPregúntame cualquier cosa sobre tu dinero:',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(ColorConfig.textPrimary),
            ),
          ),
          const SizedBox(height: 16),
          for (final q in const [
            '¿Cuánto gasté este fin de semana?',
            '¿Puedo salir a cenar y ahorrar S/ 200 este mes?',
            '¿Cuánto le he yapeado a mi pareja?',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: () => onAsk(q),
                child: Text(q, textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickSuggestions extends StatelessWidget {
  const _QuickSuggestions({required this.onAsk});

  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final q in const [
              '¿Cómo voy con mi presupuesto?',
              'Mi mayor gasto este mes',
              '¿Gasto hormiga en esta semana?',
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(q),
                  onPressed: () => onAsk(q),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Pregúntale a tu CFO…',
                  filled: true,
                  fillColor: const Color(ColorConfig.surfaceAlt),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => onSend(controller.text),
              icon: const Icon(Icons.send),
              tooltip: 'Enviar',
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatTurn message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final color = isUser
        ? const Color(ColorConfig.accent)
        : const Color(ColorConfig.surfaceAlt);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(
          message.text,
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Color(ColorConfig.textPrimary),
          ),
        ),
      ),
    );
  }
}