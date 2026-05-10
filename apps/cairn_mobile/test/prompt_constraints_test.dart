/// Regression tests for OPT-2 (Sprint 2): Rule 11 output-size constraints.
///
/// Verifies that:
/// 1. The Flutter asset copy contains every Rule 11 constraint phrase.
/// 2. The docs/ canonical copy and the Flutter asset copy are byte-identical.
/// 3. The describe_photo TURN TYPES section references Rule 11.
///
/// These tests are the Dart-side complement to the Python gate in
/// `scripts/tests/test_prompt_sync.py`. Both must pass before ship.
///
/// Fix failures by editing `docs/prompts/system_prompt_v1.txt`, then running:
///   Windows: apps\cairn_mobile\tool\sync_assets.ps1
///   Unix:    apps/cairn_mobile/tool/sync_assets.sh
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Paths are relative to the package root, which is the CWD for `flutter test`.
const _assetPath = 'assets/prompts/system_prompt_v1.txt';
const _docsPath = '../../docs/prompts/system_prompt_v1.txt';

void main() {
  late String assetText;
  late List<int> assetBytes;

  setUpAll(() {
    final assetFile = File(_assetPath);
    expect(assetFile.existsSync(), isTrue,
        reason: 'Asset missing: $_assetPath — run tool/sync_assets.ps1');
    assetBytes = assetFile.readAsBytesSync();
    assetText = String.fromCharCodes(assetBytes);
  });

  // ---------------------------------------------------------------------------
  // Rule 11 — constraint phrases must be present in the asset
  // ---------------------------------------------------------------------------

  group('Rule 11 — output size constraints in asset', () {
    test('Rule 11 heading is present', () {
      expect(assetText, contains('OUTPUT SIZE LIMITS'),
          reason:
              'Rule 11 heading missing — add it to the prompt (docs/ first, then sync)');
    });

    test('model_description 3-sentence limit is present', () {
      expect(assetText, contains('maximum 3 sentences'),
          reason:
              'Rule 11: "maximum 3 sentences" constraint missing from prompt');
    });

    test('model_description 60-word limit is present', () {
      expect(assetText, contains('maximum 60 words'),
          reason: 'Rule 11: "maximum 60 words" constraint missing from prompt');
    });

    test('model_tags 1-to-4 constraint is present', () {
      expect(assetText, contains('1 to 4 values'),
          reason:
              'Rule 11: "1 to 4 values" tags constraint missing from prompt');
    });

    test('JSON-only constraint is present', () {
      expect(assetText, contains('Return JSON only'),
          reason: 'Rule 11 must forbid prose outside the JSON object');
    });

    test('35-word preferred limit is present', () {
      expect(assetText, contains('maximum 35 words'),
          reason: 'Rule 11 preferred hot-path decode limit missing');
    });

    test('bbox at-most-1-box constraint is present', () {
      expect(assetText, contains('1 box per high-severity'),
          reason:
              'Rule 11: "1 box per high-severity" bbox constraint missing from prompt');
    });

    test('Rule 11 note on decode-time rationale is present', () {
      expect(assetText, contains('Shorter output reduces decode time'),
          reason:
              'Rule 11 rationale line missing — helps the model understand why terse output matters');
    });
  });

  // ---------------------------------------------------------------------------
  // describe_photo TURN TYPES section references Rule 11
  // ---------------------------------------------------------------------------

  group('describe_photo TURN TYPES section', () {
    test('references Rule 11 inline', () {
      expect(assetText, contains('Rule 11'),
          reason:
              'TURN TYPES describe_photo must reference Rule 11 for inline visibility');
    });

    test('references maximum 3 sentences near task = "describe_photo"', () {
      final idx = assetText.indexOf('task = "describe_photo"');
      expect(idx, isNot(-1), reason: 'describe_photo task block not found');
      // The TURN TYPES section ends before the next task block; check the 500
      // chars immediately following the task label.
      final section = assetText.substring(idx, idx + 500);
      expect(section, contains('3 sentences'),
          reason:
              'describe_photo TURN TYPES section must mention "3 sentences" constraint inline');
    });
  });

  // ---------------------------------------------------------------------------
  // Byte-identity with docs/ canonical copy
  // ---------------------------------------------------------------------------

  group('byte-identity with docs/ canonical copy', () {
    test('docs/ and assets/ copies are byte-identical', () {
      final docsFile = File(_docsPath);
      if (!docsFile.existsSync()) {
        // docs/ may not exist in CI environments that only have the app tree.
        // Skip rather than fail if the canonical source is absent.
        markTestSkipped(
            'docs copy not found at $_docsPath — skipping identity check');
        return;
      }
      final docsBytes = docsFile.readAsBytesSync();
      expect(assetBytes, equals(docsBytes),
          reason: 'docs/ and assets/ prompt copies are out of sync.\n'
              'Run tool/sync_assets.ps1 (Windows) or tool/sync_assets.sh to fix.');
    });
  });
}
