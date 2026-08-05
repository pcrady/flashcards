import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Text that renders LaTeX embedded between `$…$` (inline) or `$$…$$`
/// (display style) delimiters; everything else is plain text. Invalid
/// LaTeX falls back to showing the raw source, so a stray `$` never
/// breaks the UI.
class TexText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Lets the text be selected and copied. Off by default, and only ever
  /// safe on text nothing can be clicked through: the [SelectionArea] it
  /// needs puts a translucent tap-and-pan recognizer over its subtree,
  /// which steals clicks from buttons underneath and takes keyboard focus
  /// away from whatever owns the screen's shortcuts.
  final bool selectable;

  const TexText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.selectable = false,
  });

  static final _mathPattern =
      RegExp(r'\$\$(.+?)\$\$|\$(.+?)\$', dotAll: true);

  @override
  Widget build(BuildContext context) {
    final content = _buildText(context);
    return selectable ? SelectionArea(child: content) : content;
  }

  Widget _buildText(BuildContext context) {
    final matches = _mathPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: style, textAlign: textAlign);
    }

    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final display = m.group(1) != null;
      final tex = (m.group(1) ?? m.group(2))!.trim();
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          tex,
          mathStyle: display ? MathStyle.display : MathStyle.text,
          textStyle: effectiveStyle,
          onErrorFallback: (_) =>
              Text(text.substring(m.start, m.end), style: effectiveStyle),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: textAlign,
    );
  }
}
