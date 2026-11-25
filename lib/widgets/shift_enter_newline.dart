import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Wraps a text field whose plain Enter submits, so that Shift+Enter
/// inserts a newline at the cursor instead. The key event is handled here,
/// before it reaches the text input system, so `onSubmitted` never fires.
class ShiftEnterNewline extends StatelessWidget {
  final TextEditingController controller;
  final Widget child;

  const ShiftEnterNewline({
    super.key,
    required this.controller,
    required this.child,
  });

  void _insertNewline() {
    final value = controller.value;
    final sel = value.selection;
    final text = value.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, shift: true):
            _insertNewline,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
            _insertNewline,
      },
      child: child,
    );
  }
}
