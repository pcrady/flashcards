import 'package:flutter/material.dart';

import '../models.dart';
import '../services/claude_service.dart';
import '../services/llm_service.dart';
import '../theme.dart';
import 'tag_chips.dart';
import 'tex_text.dart';

/// Rewrites [plan] against [deck]'s own tag list before it is reviewed:
/// model-supplied tags take the deck's spelling, tags the model invented
/// are dropped, and retags naming no card — or leaving a card's tags as
/// they already are — fall away.
DeckEditPlan canonicalizePlan(Deck deck, DeckEditPlan plan) {
  String norm(String s) => s.trim().toLowerCase();

  List<String> clean(List<String> tags) {
    final out = <String>[];
    for (final t in tags) {
      final match = deck.findTag(t);
      if (match != null && !out.contains(match)) out.add(match);
    }
    return out;
  }

  final retags = <({String target, List<String> tags})>[];
  for (final r in plan.retags) {
    final tags = clean(r.tags);
    final changes = deck.cards
        .where((c) => norm(c.target) == norm(r.target))
        .any((c) =>
            c.tags.length != tags.length || !tags.every(c.tags.contains));
    if (changes) retags.add((target: r.target, tags: tags));
  }

  return DeckEditPlan(
    additions: [
      for (final a in plan.additions)
        (native: a.native, target: a.target, tags: clean(a.tags)),
    ],
    removals: plan.removals,
    retags: retags,
  );
}

/// Dialog flow for editing a deck with an LLM: the user types an
/// instruction, the model proposes additions/removals, and the user
/// reviews them with checkboxes before applying. Pops with the approved
/// [DeckEditPlan], or null if cancelled.
class AiDeckEditDialog extends StatefulWidget {
  final Deck deck;
  const AiDeckEditDialog({super.key, required this.deck});

  @override
  State<AiDeckEditDialog> createState() => _AiDeckEditDialogState();
}

class _AiDeckEditDialogState extends State<AiDeckEditDialog> {
  final _instructionController = TextEditingController();
  bool _loading = false;
  String? _error;
  DeckEditPlan? _plan;
  late List<bool> _addSelected;
  late List<bool> _removeSelected;
  late List<bool> _tagSelected;

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await LlmService.editDeck(
        instruction: instruction,
        targetLanguage: widget.deck.targetLanguage,
        nativeLanguage: widget.deck.nativeLanguage,
        subject:
            widget.deck.isLanguage ? null : widget.deck.kind.label,
        existingCards: [
          for (final c in widget.deck.cards)
            {
              'native': c.native,
              'target': c.target,
              if (widget.deck.tags.isNotEmpty) 'tags': c.tags,
            },
        ],
        availableTags: widget.deck.tags,
      );
      if (!mounted) return;
      final plan = canonicalizePlan(widget.deck, raw);
      if (plan.isEmpty) {
        setState(() => _error =
            'The model suggested no changes for that instruction.');
        return;
      }
      setState(() {
        _plan = plan;
        _addSelected = List.filled(plan.additions.length, true);
        _removeSelected = List.filled(plan.removals.length, true);
        _tagSelected = List.filled(plan.retags.length, true);
      });
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply() {
    final plan = _plan!;
    Navigator.pop(
      context,
      DeckEditPlan(
        additions: [
          for (var i = 0; i < plan.additions.length; i++)
            if (_addSelected[i]) plan.additions[i],
        ],
        removals: [
          for (var i = 0; i < plan.removals.length; i++)
            if (_removeSelected[i]) plan.removals[i],
        ],
        retags: [
          for (var i = 0; i < plan.retags.length; i++)
            if (_tagSelected[i]) plan.retags[i],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome, size: 22, color: SprakTheme.neon),
          const SizedBox(width: 10),
          const Text('Edit with AI'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: _plan == null ? _buildInput() : _buildReview(),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_plan == null)
          FilledButton.icon(
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: SprakTheme.onFjord),
                  )
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(_loading ? 'Thinking…' : 'Generate'),
            onPressed: _loading ? null : _generate,
          )
        else
          FilledButton(
            onPressed: (_addSelected.contains(true) ||
                    _removeSelected.contains(true) ||
                    _tagSelected.contains(true))
                ? _apply
                : null,
            child: const Text('Apply changes'),
          ),
      ],
    );
  }

  Widget _buildInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.deck.tags.isEmpty
              ? 'Describe a change to “${widget.deck.name}” and the AI will '
                  'propose cards to add or remove — you approve before '
                  'anything is saved.'
              : 'Describe a change to “${widget.deck.name}” and the AI will '
                  'propose cards to add or remove, and tags to apply from '
                  'this set\'s list — you approve before anything is saved.',
          style: TextStyle(color: SprakTheme.inkSoft, fontSize: 13),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _instructionController,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: 'e.g. create the cards for the numbers 1–10',
          ),
          onSubmitted: (_) => _generate(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final example in [
              // Tagging is only worth suggesting once the set has tags.
              if (widget.deck.tags.isNotEmpty &&
                  widget.deck.cards.isNotEmpty)
                'Tag every card',
              ...switch (widget.deck.kind) {
                DeckKind.language => const [
                    'Numbers 1–10',
                    'Days of the week',
                    'Common greetings',
                    'Remove the hardest cards',
                  ],
                DeckKind.math => const [
                    'Derivative rules',
                    'Squares up to 15²',
                    'Basic trig identities',
                    'Remove the hardest cards',
                  ],
                DeckKind.general => const [
                    'World capitals',
                    'Planets of the solar system',
                    'Remove the hardest cards',
                  ],
              },
            ])
              ActionChip(
                label: Text(example, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  _instructionController.text = example;
                  _generate();
                },
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  Widget _buildReview() {
    final plan = _plan!;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 440),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (plan.additions.isNotEmpty) ...[
              Text('Add ${plan.additions.length} '
                  '${plan.additions.length == 1 ? "card" : "cards"}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: SprakTheme.success)),
              const SizedBox(height: 4),
              for (var i = 0; i < plan.additions.length; i++)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _addSelected[i],
                  onChanged: (v) =>
                      setState(() => _addSelected[i] = v ?? false),
                  title: TexText(plan.additions[i].target,
                      style: SprakTheme.vocab(size: 16)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TexText(plan.additions[i].native,
                          style: TextStyle(
                              color: SprakTheme.inkSoft, fontSize: 12)),
                      if (plan.additions[i].tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: TagChips(plan.additions[i].tags),
                        ),
                    ],
                  ),
                ),
            ],
            if (plan.removals.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Remove ${plan.removals.length} '
                  '${plan.removals.length == 1 ? "card" : "cards"}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: SprakTheme.danger)),
              const SizedBox(height: 4),
              for (var i = 0; i < plan.removals.length; i++)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _removeSelected[i],
                  onChanged: (v) =>
                      setState(() => _removeSelected[i] = v ?? false),
                  title: TexText(
                    plan.removals[i],
                    style: const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: SprakTheme.danger,
                    ),
                  ),
                ),
            ],
            if (plan.retags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Retag ${plan.retags.length} '
                  '${plan.retags.length == 1 ? "card" : "cards"}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: SprakTheme.neon)),
              const SizedBox(height: 4),
              for (var i = 0; i < plan.retags.length; i++)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _tagSelected[i],
                  onChanged: (v) =>
                      setState(() => _tagSelected[i] = v ?? false),
                  title: TexText(plan.retags[i].target,
                      style: SprakTheme.vocab(size: 16)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: plan.retags[i].tags.isEmpty
                        ? Text('Clear all tags',
                            style: TextStyle(
                                color: SprakTheme.inkSoft, fontSize: 12))
                        : TagChips(plan.retags[i].tags),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
