import 'package:flutter/material.dart';

import '../services/claude_service.dart';
import '../services/llm_service.dart';
import '../theme.dart';

/// AI tutor conversation panel shown under the quiz workspace. The learner
/// can ask questions about the language; the current card is passed as
/// context so "why is it spelled like that?" just works.
class ChatBox extends StatefulWidget {
  final String targetLanguage;
  final String nativeLanguage;
  final String Function()? currentContextBuilder;

  const ChatBox({
    super.key,
    required this.targetLanguage,
    required this.nativeLanguage,
    this.currentContextBuilder,
  });

  @override
  State<ChatBox> createState() => _ChatBoxState();
}

class _ChatBoxState extends State<ChatBox> {
  final List<ChatMessage> _messages = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _error;
  String? _providerLabel;

  @override
  void initState() {
    super.initState();
    LlmService.activeProvider().then((p) {
      if (mounted) setState(() => _providerLabel = p.label);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(ChatMessage('user', text));
      _controller.clear();
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final reply = await LlmService.chat(
        history: _messages,
        targetLanguage: widget.targetLanguage,
        nativeLanguage: widget.nativeLanguage,
        currentContext: widget.currentContextBuilder?.call(),
      );
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage('assistant', reply)));
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        // Drop the unanswered user turn so history stays alternating.
        if (_messages.isNotEmpty && _messages.last.role == 'user') {
          _controller.text = _messages.removeLast().text;
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: SprakTheme.panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                Icon(Icons.psychology_alt_outlined,
                    size: 20, color: SprakTheme.neon),
                const SizedBox(width: 8),
                Text(
                  'Ask about ${widget.targetLanguage}',
                  style: TextStyle(
                    color: SprakTheme.neon,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.6,
                  ),
                ),
                if (_providerLabel != null) ...[
                  const Spacer(),
                  Text(
                    _providerLabel!,
                    style: TextStyle(
                        color: SprakTheme.inkSoft, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Ask anything — grammar, pronunciation, why an answer '
                      'is what it is…',
                      style: TextStyle(color: SprakTheme.inkSoft),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 4),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final isUser = m.role == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 520),
                          decoration: BoxDecoration(
                            color: isUser ? null : SprakTheme.surface,
                            gradient: isUser
                                ? const LinearGradient(colors: [
                                    Color(0xFF7B5CF0),
                                    SprakTheme.magenta,
                                  ])
                                : null,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isUser ? 16 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 16),
                            ),
                            border: isUser
                                ? null
                                : Border.all(color: SprakTheme.line),
                          ),
                          child: SelectableText(
                            m.text,
                            style: TextStyle(
                              color: isUser ? Colors.white : SprakTheme.ink,
                              height: 1.4,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_sending,
                    decoration: InputDecoration(
                      hintText:
                          'Ask a question about ${widget.targetLanguage}…',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 10),
                _sending
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: SprakTheme.fjord,
                          foregroundColor: SprakTheme.onFjord,
                        ),
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        onPressed: _send,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
