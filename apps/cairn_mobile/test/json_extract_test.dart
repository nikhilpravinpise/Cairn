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

    test('escaped quote inside string does not close the string (regression)',
        () {
      // Regression for the `r'\\'` comparison bug: before the fix the
      // escape-state machine never toggled, so `\"` looked like end-of-string
      // and everything after `}` in the value was mis-classified.
      final got = extractFirstJsonObject(r'{"k": "he said \"ok\" then }", "n":1}');
      expect(got, equals({'k': r'he said "ok" then }', 'n': 1}));
    });

    test('escaped backslash pair inside string', () {
      final got = extractFirstJsonObject(r'{"path": "a\\b", "ok": true}');
      expect(got, equals({'path': r'a\b', 'ok': true}));
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
