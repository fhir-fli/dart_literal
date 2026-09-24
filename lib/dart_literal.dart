/// Renders decoded JSON as Dart source that passes very_good_analysis with
/// no `ignore_for_file` header, so generated data files can sit under the
/// same lint gate as hand-written code.
///
/// Extracted 2026-09-22 from cicada_generator, where JSON-as-Dart output
/// carried 34,882 lint hits; bw-amr-ig's `_genonce.sh` did the same with an
/// inline Python `json.dumps`. One writer, used by every generator.
///
/// Rules the output follows:
/// * strings are single-quoted, or double-quoted where the piece holds an
///   apostrophe and no double quote (`prefer_single_quotes`,
///   `avoid_escaping_inner_quotes`);
/// * a string that would pass [lineWidth] is split into adjacent literals at
///   spaces, or at `;`/`,` for delimited code lists
///   (`lines_longer_than_80_chars`); lines holding a URI are exempt from
///   that lint, so an unsplittable URL is left whole;
/// * every map entry and list item ends in a comma, so `dart format` keeps
///   one entry per line (`require_trailing_commas`);
/// * maps keep their key order; numbers, booleans and null print as Dart
///   literals. Anything else is a defect in the source data.
///
/// Adjacent literals inside a list trip `no_adjacent_strings_in_list`,
/// whose purpose is to catch a missing comma, which a serializer cannot
/// produce. A document that needed such a split reports [splitInList], and
/// [header] carries the scoped `ignore_for_file` for that one rule.
class DartLiteralWriter {
  DartLiteralWriter({this.lineWidth = 80});

  /// The column the lint allows; `lines_longer_than_80_chars` says 80.
  final int lineWidth;

  bool _splitInList = false;
  bool _hardCut = false;

  /// Whether [literal] had to split a string that sits directly in a list.
  bool get splitInList => _splitInList;

  /// Whether [literal] had to cut inside a token (no separator in reach),
  /// which `missing_whitespace_between_adjacent_strings` reads as a lost
  /// space.
  bool get hardCut => _hardCut;

  /// The file header this document needs: empty, or the scoped ignores.
  String get header {
    final rules = [
      if (_splitInList) 'no_adjacent_strings_in_list',
      if (_hardCut) 'missing_whitespace_between_adjacent_strings',
    ];
    if (rules.isEmpty) return '';
    return '// ignore_for_file: ${rules.join(', ')}\n'
        '// Generated data: long strings are split into adjacent literals so\n'
        '// no line passes $lineWidth columns; a serializer cannot drop a comma\n'
        '// or a space.\n\n';
  }

  /// [value] as a Dart expression, indented [indent] levels of two spaces.
  String literal(
    Object? value, {
    int indent = 0,
    bool inList = false,
    int firstLineUsed = 0,
  }) {
    final pad = '  ' * indent;
    final inner = '  ' * (indent + 1);
    if (value == null) return 'null';
    if (value is bool || value is num) return '$value';
    if (value is String) {
      final out = _string(value, indent, firstLineUsed: firstLineUsed);
      if (inList && (out.contains("' '") || out.contains('" "'))) {
        _splitInList = true;
      }
      return out;
    }
    if (value is Map) {
      if (value.isEmpty) return '<String, dynamic>{}';
      final sb = StringBuffer('{\n');
      for (final entry in value.entries) {
        final key = _string(entry.key as String, indent + 1);
        // A string value's first piece shares the key's line.
        final value_ = literal(
          entry.value,
          indent: indent + 1,
          firstLineUsed: key.length + 2,
        );
        sb.writeln('$inner$key: $value_,');
      }
      sb.write('$pad}');
      return sb.toString();
    }
    if (value is List) {
      if (value.isEmpty) return '<dynamic>[]';
      final sb = StringBuffer('[\n');
      for (final item in value) {
        sb.writeln(
          '$inner${literal(item, indent: indent + 1, inList: true)},',
        );
      }
      sb.write('$pad]');
      return sb.toString();
    }
    throw ArgumentError('Cannot render ${value.runtimeType} as a Dart literal');
  }

  /// A string literal, split into adjacent literals when it would not fit.
  /// `dart format` puts each continuation on its own line, indented four
  /// more than the first piece, and the compiler joins them.
  String _string(String s, int indent, {int firstLineUsed = 0}) {
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll(r'$', r'\$')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    // Size every piece for the continuation position: width minus indent,
    // the extra 4, the quotes, and ", " or "," after it.
    final room = lineWidth - 2 * (indent + 1) - 4 - 2 - 2;
    // One piece stays whole when it fits after the key on the key's line,
    // or alone on the line below it (the formatter moves it there). Once a
    // string is split, `dart format` (tall style, SDK 3.7+) puts the key on
    // its own line and EVERY piece at the continuation position, so the
    // first piece is sized like the rest. Measured 2026-09-23 with Dart
    // 3.13: sizing the first piece for the key's line cut it short for
    // nothing.
    final firstRoom = lineWidth - 2 * (indent + 1) - firstLineUsed - 2 - 1;
    if (escaped.length <= firstRoom || escaped.length <= room + 1) {
      return _quote(escaped);
    }
    // `lines_longer_than_80_chars` exempts a line whose string literal
    // holds a `/` or a `\` (pkg/linter, `_looksLikeUriOrPath`, read
    // 2026-09-23): "We make an exception for URIs and file paths ... This
    // makes it easier to search source files for a given path." Such a
    // string stays whole, however long.
    if (escaped.contains('/') || escaped.contains(r'\')) {
      return _quote(escaped);
    }
    final sep =
        escaped.contains(' ')
            ? ' '
            : escaped.contains(';')
            ? ';'
            : ',';
    final pieces = <String>[];
    var rest = escaped;
    while (rest.length > room) {
      final limit = room;
      var cut = rest.lastIndexOf(sep, limit - 1);
      // No separator in reach (a long HTML attribute, a long token): cut
      // after the last non-word character instead, which the whitespace
      // lint accepts; only a cut inside one word (letters on both sides)
      // trips it, and that is reported. Never cut between a backslash and
      // the character it escapes.
      if (cut <= 0) {
        cut = limit - 1;
        while (cut > 0 && _isWord(rest[cut])) {
          cut--;
        }
        if (cut <= 0) {
          _hardCut = true;
          cut = limit - 1;
        }
        var slashes = 0;
        while (cut - slashes >= 0 && rest[cut - slashes] == r'\') {
          slashes++;
        }
        if (slashes.isOdd) cut--;
      }
      pieces.add(rest.substring(0, cut + 1));
      rest = rest.substring(cut + 1);
    }
    pieces.add(rest);
    return pieces.map(_quote).join(' ');
  }

  static bool _isWord(String ch) => RegExp(r'\w').hasMatch(ch);

  /// [piece] is already escaped. A piece whose only escapes are `\\` or
  /// `\$` and that holds no quote goes out raw (`use_raw_strings`).
  static String _quote(String piece) {
    if (piece.contains("'") && !piece.contains('"')) return '"$piece"';
    final hasEscape = piece.contains(r'\');
    if (hasEscape &&
        !piece.contains("'") &&
        !RegExp(r'\\[nrt"]').hasMatch(piece)) {
      final raw = piece.replaceAll(r'\$', r'$').replaceAll(r'\\', r'\');
      return "r'$raw'";
    }
    return "'${piece.replaceAll("'", r"\'")}'";
  }
}

/// A complete Dart file holding one JSON document:
///
/// ```dart
/// import 'package:fhir_r4/fhir_r4.dart' show ValueSet;
///
/// final ValueSet name = ValueSet.fromJson({...});
/// ```
///
/// [comment] lines go above the declaration as `///` documentation. The
/// caller runs `dart format` on the result (or uses `bin/json_to_dart.dart`,
/// which does).
String dartFileForJson({
  required Object? json,
  required String type,
  required String name,
  String import = 'package:fhir_r4/fhir_r4.dart',
  List<String> comment = const [],
}) {
  final writer = DartLiteralWriter();
  // The literal is the argument of `fromJson(`, so dart format indents it one
  // level: size the pieces for that.
  final body = writer.literal(json, indent: 1);
  final doc = comment.map((line) => '/// $line\n').join();
  return '${writer.header}'
      "import '$import' show $type;\n\n"
      '$doc'
      'final $type $name = $type.fromJson(\n  $body,\n);\n';
}
