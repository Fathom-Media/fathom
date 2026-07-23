@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the trap documented on [kInlineButtonStyle].
///
/// The app's button themes set `minimumSize: Size.fromHeight(52)`, which is
/// `Size(double.infinity, 52)` — an infinite minimum width. A Row hands non-flex
/// children unbounded width, so such a button demands infinity, RenderFlex
/// throws, and Flutter silently skips painting it. It looks like a data bug and
/// costs hours. This test finds the pattern in source instead: a Filled/Outlined
/// button whose nearest enclosing widget is a Row, with no local style.
///
/// If this fails, either add `style: kInlineButtonStyle` to the button, or wrap
/// it in Expanded/Flexible/SizedBox so its width is bounded.
void main() {
  test('no themed Filled/Outlined button sits bare in a Row', () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (file.path.endsWith('app_theme.dart')) continue;
      final lines = file.readAsStringSync().split('\n');

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!RegExp(r'\b(FilledButton|OutlinedButton)\b').hasMatch(line)) {
          continue;
        }
        if (RegExp(r'styleFrom|ThemeData|ButtonStyle|^\s*//').hasMatch(line)) {
          continue;
        }

        // The button's own arguments: does it set its own minimum width?
        final indent = line.length - line.trimLeft().length;
        var hasLocalStyle = false;
        for (var j = i + 1; j < lines.length; j++) {
          final l = lines[j];
          if (l.trim().isEmpty) continue;
          final ind = l.length - l.trimLeft().length;
          if (ind <= indent) break;
          if (ind == indent + 2 &&
              RegExp(r'style: (kInlineButtonStyle|FilledButton\.styleFrom|'
                      r'OutlinedButton\.styleFrom|ButtonStyle)')
                  .hasMatch(l.trim().isEmpty ? l : l)) {
            hasLocalStyle = true;
            break;
          }
        }
        if (hasLocalStyle) continue;

        // Walk out to the nearest enclosing widget. Matching is by word
        // boundary, not by line prefix: constructors show up mid-line too
        // ("child: Row(", "builder: (ctx) => AlertDialog("), and missing those
        // walks straight past a dialog into whatever Row happens to be above
        // it, which reports a button that is perfectly safe.
        final widget = RegExp(r'\b(Row|Column|ListView|Center|Wrap|SizedBox|'
            r'Expanded|Flexible|AlertDialog|SimpleDialog|Dialog|'
            r'SingleChildScrollView|OverflowBar|ButtonBar|Card|Container|'
            r'Padding|Align|ConstrainedBox|IntrinsicWidth)\(');
        String? parent;
        var cur = indent;
        for (var j = i - 1; j >= 0 && j > i - 60; j--) {
          final l = lines[j];
          if (l.trim().isEmpty) continue;
          final ind = l.length - l.trimLeft().length;
          if (ind >= cur) continue;
          cur = ind;
          final m = widget.firstMatch(l);
          if (m != null) {
            parent = m.group(1);
            break;
          }
        }

        if (parent == 'Row') {
          offenders.add('${file.path}:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'These buttons sit directly in a Row and inherit the theme\'s '
            'infinite minimum width, so they throw during layout and are never '
            'painted. Add style: kInlineButtonStyle, or wrap in '
            'Expanded/Flexible/SizedBox:\n  ${offenders.join('\n  ')}');
  });
}
