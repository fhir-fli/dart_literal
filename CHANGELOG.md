## 0.1.1

- A split string's first piece is sized like the rest. `dart format` (tall
  style) puts a split map value under its key with every piece at one
  position, so sizing the first piece for the key's line only cut it short.
  A string that fits whole on the line below the key stays one piece.
- `.dart_tool/` was tracked; now ignored.

# dart_literal

## [0.1.0]

- `DartLiteralWriter`, `dartFileForJson` and the `json_to_dart` command, moved
  out of fhir_generator (private) so public packages can depend on them.
