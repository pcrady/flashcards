import 'package:flutter/material.dart';

import '../theme.dart';
import 'tex_text.dart';

/// A card's free-form note — a meaning nuance, an example sentence, a
/// mnemonic — shown as a quiet panel with a left accent rule so it never
/// competes with the card's two sides. LaTeX between `$…$` renders, so
/// math decks can annotate too.
class CardNote extends StatelessWidget {
  final String notes;
  final double fontSize;

  /// Lets the note be selected and copied. Only safe where nothing
  /// clickable sits underneath — see [TexText.selectable].
  final bool selectable;

  const CardNote(
    this.notes, {
    super.key,
    this.fontSize = 13,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: SprakTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: SprakTheme.fjord, width: 2.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: fontSize * 0.15),
            child: Icon(Icons.sticky_note_2_outlined,
                size: fontSize + 1, color: SprakTheme.inkSoft),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: TexText(
              notes,
              style: TextStyle(
                color: SprakTheme.inkSoft,
                fontSize: fontSize,
                height: 1.35,
              ),
              selectable: selectable,
            ),
          ),
        ],
      ),
    );
  }
}
