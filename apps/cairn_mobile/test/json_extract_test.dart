import 'package:cairn_mobile/core/llm/json_extract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractFirstJsonObject', () {
    test('plain object', () {
      final got = extractFirstJsonObject('{"a": 1}');
      expect(got, equals({'a': 1}));
    });

    test('object with leading prose', () {
      final got = extractFirstJsonObject(
          'Sure, here you go:\n```\n{"a": 1, "b": "two"}\n```');
      expect(got, equals({'a': 1, 'b': 'two'}));
    });

    test('nested objects', () {
      final got = extractFirstJsonObject(
          'cot: thinking… {"outer": {"inner": [1,2,3]}, "tail": true}');
      expect(got, equals({
        'outer': {'inner': [1, 2, 3]},
        'tail': true,
      }));
    });

    test('object with brace inside string', () {
      final got = extractFirstJsonObject(r'{"k": "v with } brace"}');
      expect(got, equals({'k': 'v with } brace'}));
    });

    test('returns null on no object', () {
      expect(extractFirstJsonObject('no json here'), isNull);
      expect(extractFirstJsonObject(''), isNull);
    });

    test('returns null on malformed', () {
      expect(extractFirstJsonObject('{"a": }'), isNull);
    });
  });
}
