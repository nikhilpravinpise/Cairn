/// Regression tests for the trimmed vision-task system prompts.
///
/// These guard `system_prompt_vision_v1.txt` (conservative) and
/// `system_prompt_vision_aggressive_v1.txt` (aggressive). Both are served
/// to describe_photo turns via [systemPromptForProfileProvider] when
/// `BENCH_PROMPT` selects them, so they must retain:
///
/// 1. JSON-only and output-size constraints (model can't drift to verbose prose).
/// 2. The full model_tags enum (so the contract validator never sees a tag
///    the prompt didn't teach).
/// 3. The describe_photo task label (so the model knows which turn this is).
///
/// Byte-identity with `docs/prompts/` is enforced via the sync script.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _visionAssetPath = 'assets/prompts/system_prompt_vision_v1.txt';
const _visionAggressiveAssetPath =
    'assets/prompts/system_prompt_vision_aggressive_v1.txt';

const _visionDocsPath = '../../docs/prompts/system_prompt_vision_v1.txt';
const _visionAggressiveDocsPath =
    '../../docs/prompts/system_prompt_vision_aggressive_v1.txt';

// The full tag enum from docs/schema/evidence_packet_v1.schema.json — every
// vision prompt MUST teach all of these so the contract validator can never
// reject a model output for using a tag the prompt didn't authorize.
const _kRequiredTags = <String>[
  'diagonal_crack',
  'horizontal_crack',
  'vertical_crack',
  'x_pattern_crack',
  'concrete_spalling',
  'exposed_rebar',
  'column_base_damage',
  'beam_column_joint_damage',
  'soft_story_condition',
  'pounding_damage',
  'infill_wall_crack',
  'out_of_plane_failure',
  'foundation_displacement',
  'chimney_damage',
  'parapet_damage',
  'falling_hazard_unsecured',
  'uncertain_structural',
  'uncertain_cosmetic',
  'no_visible_damage',
];

void main() {
  for (final spec in const <_PromptSpec>[
    _PromptSpec(
      label: 'conservative',
      assetPath: _visionAssetPath,
      docsPath: _visionDocsPath,
    ),
    _PromptSpec(
      label: 'aggressive',
      assetPath: _visionAggressiveAssetPath,
      docsPath: _visionAggressiveDocsPath,
    ),
  ]) {
    group('${spec.label} vision prompt — ${spec.assetPath}', () {
      late String text;
      late List<int> bytes;

      setUpAll(() {
        final file = File(spec.assetPath);
        expect(file.existsSync(), isTrue,
            reason: 'Asset missing: ${spec.assetPath} — run tool/sync_assets.sh');
        bytes = file.readAsBytesSync();
        text = String.fromCharCodes(bytes);
      });

      test('JSON-only constraint is present', () {
        // "Return JSON only" (conservative copies the Rule 11 phrasing); the
        // aggressive variant uses "Return JSON only" too. Both are accepted.
        expect(text.contains('Return JSON only') || text.contains('STRICT JSON'),
            isTrue,
            reason: 'vision prompt must forbid prose outside the JSON object');
      });

      test('describe_photo task label is present', () {
        expect(text, contains('describe_photo'),
            reason: 'vision prompt must name the describe_photo task');
      });

      test('model_description size limits are present', () {
        expect(text, contains('maximum 3 sentences'),
            reason: '3-sentence ceiling missing — describe_photo decode time '
                'depends on this bound');
        expect(text, contains('maximum 60 words'),
            reason: '60-word ceiling missing');
        expect(text, contains('maximum 35 words'),
            reason: '35-word preferred ceiling missing');
      });

      test('model_tags 1-to-4 constraint is present', () {
        expect(text, contains('1 to 4'),
            reason:
                'model_tags 1-to-4 constraint missing from vision prompt');
      });

      test('bbox at-most-1-box constraint is present', () {
        expect(text, contains('1 box per high-severity'),
            reason: 'bbox density rule missing from vision prompt');
      });

      test('every required tag appears in the prompt', () {
        final missing = <String>[
          for (final tag in _kRequiredTags)
            if (!text.contains(tag)) tag,
        ];
        expect(missing, isEmpty,
            reason:
                'vision prompt is missing tags from the schema enum: $missing\n'
                'The contract validator rejects any tag the prompt did not '
                'teach, so omitting one silently breaks describe_photo.');
      });

      test('docs/ copy is byte-identical to assets/ copy', () {
        final docsFile = File(spec.docsPath);
        if (!docsFile.existsSync()) {
          markTestSkipped(
              'docs copy not found at ${spec.docsPath} — skipping identity check');
          return;
        }
        expect(bytes, equals(docsFile.readAsBytesSync()),
            reason:
                'docs/ and assets/ copies of ${spec.label} vision prompt are '
                'out of sync.\nRun tool/sync_assets.sh (or .ps1 on Windows).');
      });
    });
  }
}

class _PromptSpec {
  const _PromptSpec({
    required this.label,
    required this.assetPath,
    required this.docsPath,
  });
  final String label;
  final String assetPath;
  final String docsPath;
}
