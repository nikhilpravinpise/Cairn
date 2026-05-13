import 'dart:convert';

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

    // ── Gemma 4 stray-empty-string repair ──────────────────────────────────
    // Regression: model emits an orphan `""` token between fields. Without
    // repair, the entire describe_photo turn fails with a misleading
    // "required tool call missing" error.
    test('repairs orphan "" token in middle of object (Gemma 4 quirk)', () {
      const raw = '{\n'
          '  "observation_id": "obs-4",\n'
          '  "",\n'
          '  "prompt_id": "f_pema154_q04",\n'
          '  "asked_in": "en",\n'
          '  "image_refs": ["img4"],\n'
          '  "model_description": "An interior view of a room.",\n'
          '  "model_tags": ["no_visible_damage"],\n'
          '  "model_confidence": 0.95,\n'
          '  "bbox_annotations": []\n'
          '}';
      final got = extractFirstJsonObject(raw);
      expect(got, isNotNull);
      expect(got!['observation_id'], 'obs-4');
      expect(got['prompt_id'], 'f_pema154_q04');
      expect(got['model_tags'], ['no_visible_damage']);
      expect(got['model_confidence'], 0.95);
    });

    test('repairs orphan "" at start of object', () {
      final got = extractFirstJsonObject('{ "", "a": 1 }');
      expect(got, equals({'a': 1}));
    });

    test('repairs orphan "" at end of object', () {
      final got = extractFirstJsonObject('{ "a": 1, "" }');
      expect(got, equals({'a': 1}));
    });

    test('does not touch valid empty string values', () {
      // `["", ""]` is valid JSON — should parse on first attempt, no repair.
      final got = extractFirstJsonObject('{"xs": ["", ""]}');
      expect(got, equals({
        'xs': ['', ''],
      }));
    });

    test('does not touch empty string keys/values inside strings', () {
      final got =
          extractFirstJsonObject(r'{"k": "contains , \"\", inside string"}');
      expect(got, equals({'k': 'contains , "", inside string'}));
    });
  });

  group('repairOrphanEmptyStrings', () {
    test('returns input unchanged when no orphan present', () {
      const s = '{"a": 1, "b": "two"}';
      expect(repairOrphanEmptyStrings(s), s);
    });

    test('strips orphan in middle', () {
      // Whitespace may differ; the important property is that the result is
      // valid JSON equivalent to the original-without-orphan.
      final repaired = repairOrphanEmptyStrings('{"a": 1, "", "b": 2}');
      expect(jsonDecode(repaired), equals({'a': 1, 'b': 2}));
    });
  });
}
