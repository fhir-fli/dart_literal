/// Writes one JSON document as a lint-clean Dart file (see
/// `DartLiteralWriter`), then formats it.
///
/// ```sh
/// dart run fhir_generator:json_to_dart \
///   --input output/ValueSet-x.json --output lib/fhir/value_set_x.dart \
///   --type ValueSet --name valueSetX [--import package:fhir_r4/fhir_r4.dart]
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_literal/dart_literal.dart';

Future<void> main(List<String> args) async {
  final parser =
      ArgParser()
        ..addOption('input', abbr: 'i', mandatory: true, help: 'JSON file')
        ..addOption('output', abbr: 'o', mandatory: true, help: 'Dart file')
        ..addOption('type', abbr: 't', mandatory: true, help: 'Dart class')
        ..addOption('name', abbr: 'n', mandatory: true, help: 'variable name')
        ..addOption(
          'import',
          defaultsTo: 'package:fhir_r4/fhir_r4.dart',
          help: 'library that exports the class',
        )
        ..addMultiOption('comment', help: 'doc comment line(s)')
        ..addFlag(
          'format',
          defaultsTo: true,
          help: 'run dart format on output',
        );
  final ArgResults opts;
  try {
    opts = parser.parse(args);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln(parser.usage);
    exitCode = 64;
    return;
  }
  final json = jsonDecode(File(opts['input'] as String).readAsStringSync());
  final out =
      File(opts['output'] as String)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          dartFileForJson(
            json: json,
            type: opts['type'] as String,
            name: opts['name'] as String,
            import: opts['import'] as String,
            comment: opts['comment'] as List<String>,
          ),
        );
  if (opts['format'] as bool) {
    final result = await Process.run('dart', ['format', out.path]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    exitCode = result.exitCode;
  }
}
