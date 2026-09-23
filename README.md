# dart_literal

Renders decoded JSON as Dart source that passes `very_good_analysis` with no
`ignore_for_file` header, so generated data files can sit under the same lint
gate as hand-written code.

```dart
import 'package:dart_literal/dart_literal.dart';

final source = dartFileForJson(
  json: {'resourceType': 'ValueSet', 'id': 'x'},
  type: 'ValueSet',
  name: 'x',
  import: 'package:fhir_r4/fhir_r4.dart',
);
```

Or from the command line:

```sh
dart run dart_literal:json_to_dart \
  --input ValueSet-x.json --output lib/value_set_x.dart \
  --type ValueSet --name valueSetX
```

Rules the output follows: single-quoted strings (double where the text holds
an apostrophe), raw strings where the only escapes are backslash or `$`,
strings split into adjacent literals at 80 columns (after a space, a `;` or
`,` in delimited lists, or a non-word character; a cut inside one word is
reported and scoped), every entry with a trailing comma so `dart format`
keeps one entry per line, map key order preserved. See `DartLiteralWriter`.

Born in the fhir-fli family's generators (cicada, bw-amr-ig, fhir_generator),
where JSON-as-Dart data files carried 34,882 lint hits.
