/// Regression tests for BUG-6: _PrettyEncoder was replaced with
/// dart:convert.JsonEncoder.withIndent.
///
/// The hand-rolled encoder only escaped double-quotes, producing invalid JSON
/// for strings containing backslashes, newlines, tabs, or control characters.
/// These tests verify that [JsonEncoder.withIndent] handles all edge cases
/// and produces valid, round-trippable JSON.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonEncoder.withIndent — round-trip correctness', () {
    const enc = JsonEncoder.withIndent('  ');

    String rt(Object? value) {
      final encoded = enc.convert(value);
      return jsonDecode(encoded) as String;
    }

    test('plain string round-trips unchanged', () {
      expect(rt('hello world'), 'hello world');
    });

    test('double-quote in string is escaped', () {
      expect(rt('say "hello"'), 'say "hello"');
    });

    test('backslash in string is escaped', () {
      expect(rt(r'C:\Users\name'), r'C:\Users\name');
    });

    test('newline in string is escaped', () {
      expect(rt('line one\nline two'), 'line one\nline two');
    });

    test('tab in string is escaped', () {
      expect(rt('col1\tcol2'), 'col1\tcol2');
    });

    test('carriage return in string is escaped', () {
      expect(rt('line\r\n'), 'line\r\n');
    });

    test('null value encodes as "null"', () {
      final json = enc.convert(null);
      expect(json, 'null');
    });

    test('bool values encode correctly', () {
      expect(enc.convert(true), 'true');
      expect(enc.convert(false), 'false');
    });

    test('nested map with special-char values round-trips', () {
      final original = {
        'description': 'Cracks at 45\u00b0 \u2014 "severe" damage\nline2',
        'path': r'C:\data\report.json',
      };
      final json = enc.convert(original);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['description'], original['description']);
      expect(decoded['path'], original['path']);
    });

    test('output is valid JSON (jsonDecode does not throw)', () {
      final data = {
        'model_tags': ['diagonal_crack', 'no_visible_damage'],
        'model_confidence': 0.85,
        'model_description': 'Diagonal crack with "significant" width\nnote',
        'bbox_annotations': [
          {'box_2d': [100, 200, 300, 400], 'label': 'crack'},
        ],
      };
      final json = enc.convert(data);
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('empty string encodes and round-trips', () {
      expect(rt(''), '');
    });

    test('unicode characters round-trip', () {
      expect(rt('Temperatura: 30\u00b0C'), 'Temperatura: 30\u00b0C');
    });
  });
}
