import 'package:dart_literal/dart_literal.dart';
import 'package:test/test.dart';

void main() {
  group('DartLiteralWriter', () {
    test('scalars', () {
      final w = DartLiteralWriter();
      expect(w.literal(null), 'null');
      expect(w.literal(true), 'true');
      expect(w.literal(3), '3');
      expect(w.literal(2.5), '2.5');
      expect(w.literal('a'), "'a'");
      expect(w.literal(<String, dynamic>{}), '<String, dynamic>{}');
      expect(w.literal(<dynamic>[]), '<dynamic>[]');
    });

    test('quotes: single by default, double around an apostrophe', () {
      final w = DartLiteralWriter();
      expect(w.literal("it's"), '"it\'s"');
      expect(w.literal('say "hi"'), "'say \"hi\"'");
      expect(w.literal('both \' and "'), "'both \\' and \"'");
    });

    test(r'escapes backslash, $, and control characters', () {
      final w = DartLiteralWriter();
      // backslash and $ alone make a raw string; control characters need
      // escapes, so those stay in a normal string
      expect(w.literal(r'a\b'), r"r'a\b'");
      expect(w.literal(r'$x'), r"r'$x'");
      expect(w.literal('a\nb\tc'), r"'a\nb\tc'");
      expect(w.literal('a\\\nb'), r"'a\\\nb'");
    });

    test('map keeps key order, one entry per line, trailing commas', () {
      final w = DartLiteralWriter();
      expect(
        w.literal({
          'b': 1,
          'a': <String, dynamic>{'c': null},
        }),
        "{\n  'b': 1,\n  'a': {\n    'c': null,\n  },\n}",
      );
    });

    test('a long string splits at spaces into adjacent literals', () {
      final w = DartLiteralWriter();
      final long = List.filled(20, 'word').join(' '); // 99 chars
      final out = w.literal(long);
      expect(out, contains("' '"));
      // the first piece may use the whole line; continuations sit 4 deeper
      final pieces = out.split("' '");
      expect(pieces.first.length, lessThanOrEqualTo(80 - 2 - 2 - 1 + 2));
      for (final piece in pieces.skip(1)) {
        expect(piece.length, lessThanOrEqualTo(80 - 2 - 4 - 2 - 2 + 2));
      }
      // joining the pieces gives the original back
      expect(out.replaceAll("' '", '').replaceAll("'", ''), long);
      expect(w.splitInList, isFalse);
      expect(w.header, isEmpty);
    });

    test('a delimited code list with no spaces splits after ;', () {
      final w = DartLiteralWriter();
      final codes = List.generate(30, (i) => '${100 + i}').join(';');
      final out = w.literal(codes, indent: 6);
      expect(out, contains(";' '"));
      expect(out.replaceAll("' '", '').replaceAll("'", ''), codes);
    });

    test('a string holding a slash or backslash stays whole, however long', () {
      // lines_longer_than_80_chars exempts a line whose string literal
      // contains `/` or `\` (the linter's _looksLikeUriOrPath), so a URL or
      // a path is never split: it stays searchable as one token.
      final w = DartLiteralWriter();
      const url =
          'https://www.cdc.gov/covid/hcp/vaccine-considerations/'
          'special-situations-and-populations.html#cdc_clinical_guidance';
      expect(w.literal(url), "'$url'");
      final path = r'C:\\Users\\' + 'x' * 120;
      expect(w.literal(path), startsWith("r'C:"));
      expect(w.literal(path), isNot(contains("' '")));
      expect(w.hardCut, isFalse);
    });

    test('a URL inside prose is one whole piece, the prose still splits', () {
      final w = DartLiteralWriter();
      const url =
          'https://www.cdc.gov/covid/hcp/vaccine-considerations/'
          'special-situations-and-populations.html#cdc_clinical_guidance';
      final prose = 'See ${'word ' * 30}$url and ${'more ' * 30}end';
      final out = w.literal(prose, indent: 5);
      final pieces = out.split("' '").map((p) => p.replaceAll("'", ''));
      expect(pieces, contains('$url '));
      for (final piece in pieces) {
        if (piece.contains('/')) continue;
        expect(piece.length, lessThanOrEqualTo(80 - 12 - 4 - 2 - 2));
      }
      expect(pieces.join(), prose);
      expect(w.hardCut, isFalse);
    });

    test('prose that holds a slash still splits at its spaces', () {
      final w = DartLiteralWriter();
      final prose = 'On 8/22/2025 the dose is 10 mcg/0.3 mL ${'again ' * 20}';
      final out = w.literal(prose);
      expect(out, contains("' '"));
      for (final piece in out.split("' '")) {
        expect(piece.length, lessThanOrEqualTo(80 - 2 - 4 - 2 - 2 + 2));
      }
      expect(out.replaceAll("' '", '').replaceAll("'", ''), prose);
    });

    test('a split inside a list is reported and earns the scoped header', () {
      final w = DartLiteralWriter();
      final long = List.filled(20, 'word').join(' ');
      w.literal([long]);
      expect(w.splitInList, isTrue);
      expect(w.header, startsWith('// ignore_for_file: no_adjacent_strings'));
    });

    test('a token longer than the room is cut hard, not left long', () {
      final w = DartLiteralWriter();
      final token = 'x' * 150;
      final out = w.literal('a $token b', indent: 4);
      for (final piece in out.split("' '")) {
        expect(piece.length, lessThanOrEqualTo(80 - 10 - 4 - 2 - 2 + 2));
      }
      expect(out.replaceAll("' '", '').replaceAll("'", ''), 'a $token b');
      expect(w.hardCut, isTrue);
      expect(w.header, contains('missing_whitespace_between_adjacent_strings'));
    });

    test('a long token is cut after a non-word character when one exists', () {
      final w = DartLiteralWriter();
      final token = List.filled(30, 'abcde').join('-'); // 179 chars, no space
      final out = w.literal(token);
      expect(w.hardCut, isFalse);
      for (final piece in out.split("' '")) {
        expect(
          piece.replaceAll("'", ''),
          endsWith('-'),
          reason: 'every piece but the last ends at a hyphen',
        );
        break;
      }
      expect(out.replaceAll("' '", '').replaceAll("'", ''), token);
    });

    test('a hard cut never splits an escape sequence', () {
      // Reassemble the emitted pieces the way the compiler would; a cut
      // inside an escape would leave a stray backslash and break this.
      String rejoin(String out) =>
          out
              .split(RegExp("' r?'"))
              .map(
                (p) => p
                    .replaceFirst(RegExp("^r?'"), '')
                    .replaceFirst(RegExp(r"'$"), ''),
              )
              .map((p) => p.replaceAll(r'\$', r'$'))
              .join();
      // A raw backslash would exempt the string from splitting altogether,
      // so the escapes under test are the ones the writer itself adds.
      final w = DartLiteralWriter();
      for (final n in [67, 68, 69, 70]) {
        final s = '${'y' * n}\$z${'w' * 5}';
        expect(rejoin(w.literal(s)), s, reason: 'n=$n');
      }
    });

    test('escapes with no quote or control character go out raw', () {
      final w = DartLiteralWriter();
      expect(w.literal(r'a\_b'), r"r'a\_b'");
      expect(w.literal(r'$5'), r"r'$5'");
      expect(w.literal('a\\\nb'), r"'a\\\nb'");
      expect(w.literal(r"it's \ here"), '"it\'s \\\\ here"');
    });

    test("a split value's pieces are all sized for the line below the key", () {
      // dart format (tall style) lays a split value out with the key alone
      // on its line and every piece four deeper, so the first piece is as
      // wide as the rest; sizing it for the key's line left it short.
      final w = DartLiteralWriter();
      final long = List.filled(30, 'word').join(' ');
      final out = w.literal({'definition': long}, indent: 3);
      final entry = out.split('\n')[1].trim();
      final pieces = entry.substring("'definition': ".length).split("' '");
      // indent 3 -> pieces at column 8 + 4; quotes and a comma after.
      const room = 80 - 12 - 2 - 2;
      for (final piece in pieces) {
        expect(piece.length, lessThanOrEqualTo(room));
      }
      // The first piece uses that room, not the shorter key line.
      expect(pieces.first.length, greaterThan(room - 'word '.length));
      // The writer's line; the formatter then moves the pieces under the key.
      expect(entry, startsWith("'definition': 'word"));
    });

    test('one piece that fits under the key stays whole', () {
      final w = DartLiteralWriter();
      // A map value sits one level in: below its key it starts at column
      // 8, so 69 characters plus quotes and a comma end at 80. That is
      // longer than the key's own line allows and shorter than a split.
      final s = 'x' * 69;
      final out = w.literal({'k': s});
      expect(out.split('\n')[1].trim(), "'k': '$s',");
    });

    test('anything else is a defect', () {
      expect(
        () => DartLiteralWriter().literal(DateTime(2026)),
        throwsArgumentError,
      );
    });
  });

  test('dartFileForJson composes a complete file', () {
    final file = dartFileForJson(
      json: {'resourceType': 'ValueSet', 'id': 'x'},
      type: 'ValueSet',
      name: 'x',
      comment: ['One line.'],
    );
    expect(file, '''
import 'package:fhir_r4/fhir_r4.dart' show ValueSet;

/// One line.
final ValueSet x = ValueSet.fromJson(
  {
    'resourceType': 'ValueSet',
    'id': 'x',
  },
);
''');
  });
}
