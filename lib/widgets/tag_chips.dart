import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Read-only pills listing the tags on a card.
class TagChips extends StatelessWidget {
  final List<String> tags;
  final double fontSize;
  const TagChips(this.tags, {super.key, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final t in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: SprakTheme.tagColor(t).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              t,
              style: TextStyle(
                color: SprakTheme.tagColor(t),
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

/// Chips for choosing which of a deck's tags apply to a card. Any number
/// can be on at once; the trailing "New tag" chip adds one to the deck.
class TagSelector extends StatefulWidget {
  final Deck deck;

  /// Tags currently applied, as canonical names from [deck.tags].
  final List<String> selected;

  /// Called with the new selection whenever a chip is toggled or a freshly
  /// created tag is applied.
  final ValueChanged<List<String>> onChanged;

  /// Called after a tag is added to the deck, so the caller can persist it.
  final VoidCallback? onTagCreated;

  const TagSelector({
    super.key,
    required this.deck,
    required this.selected,
    required this.onChanged,
    this.onTagCreated,
  });

  @override
  State<TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends State<TagSelector> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    // Clicking away from the new-tag field puts the chip back.
    _focus.addListener(() {
      if (!_focus.hasFocus && _adding) {
        _controller.clear();
        setState(() => _adding = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggle(String tag) {
    final next = List.of(widget.selected);
    if (!next.remove(tag)) next.add(tag);
    widget.onChanged(next);
  }

  void _createTag() {
    final name = widget.deck.addTag(_controller.text);
    _controller.clear();
    setState(() => _adding = false);
    if (name == null) return;
    widget.onTagCreated?.call();
    if (!widget.selected.contains(name)) {
      widget.onChanged([...widget.selected, name]);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.deck.tags.isEmpty && !_adding)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(
              'No tags in this set yet.',
              style: TextStyle(color: SprakTheme.inkSoft, fontSize: 12),
            ),
          ),
        for (final tag in widget.deck.tags)
          _SelectableTagChip(
            label: tag,
            color: SprakTheme.tagColor(tag),
            selected: widget.selected.contains(tag),
            onTap: () => _toggle(tag),
          ),
        if (_adding)
          SizedBox(
            width: 150,
            height: 32,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Tag name',
                hintStyle:
                    TextStyle(color: SprakTheme.inkSoft, fontSize: 13),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onSubmitted: (_) => _createTag(),
            ),
          )
        else
          _SelectableTagChip(
            label: 'New tag',
            selected: false,
            icon: Icons.add,
            onTap: () => setState(() => _adding = true),
          ),
      ],
    );
  }
}

/// One tappable tag chip. Applied: filled and check-marked in the tag's
/// own color. Not applied: outlined, with a dot of that color so the
/// mapping is visible before it is picked.
class _SelectableTagChip extends StatelessWidget {
  final String label;
  final bool selected;

  /// The tag's color, or null for the "New tag" chip.
  final Color? color;
  final IconData? icon;
  final VoidCallback onTap;

  const _SelectableTagChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? SprakTheme.inkSoft;
    return Material(
      color: selected ? tint.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? tint : SprakTheme.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: tint),
                const SizedBox(width: 5),
              ] else if (selected) ...[
                Icon(Icons.check, size: 14, color: tint),
                const SizedBox(width: 5),
              ] else if (color != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? SprakTheme.ink : SprakTheme.inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
