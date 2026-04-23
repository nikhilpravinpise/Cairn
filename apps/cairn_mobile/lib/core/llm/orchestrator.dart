/// LLM orchestrator — the only place that builds user-turn JSON for Gemma.
///
/// Implements the four task contracts from the locked system prompt:
///   * describe_photo
///   * ask_followup
///   * protocol_answer
///   * synthesize
///
/// Fails loud on parse / contract violations. The session controller decides
/// whether to surface the error or re-ask the model.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'gemma_session.dart';
import 'json_extract.dart';

/// Thrown when Gemma's response cannot be parsed into the expected shape.
class GemmaContractError implements Exception {
  GemmaContractError(this.message, {required this.rawText, this.task});
  final String message;
  final String rawText;
  final String? task;

  @override
  String toString() =>
      'GemmaContractError($task): $message\n--- raw ---\n$rawText\n-----------';
}

/// One run of `describe_photo`.
class DescribePhotoResult {
  const DescribePhotoResult({
    required this.observationId,
    required this.promptId,
    required this.askedIn,
    required this.imageRefs,
    required this.modelDescription,
    required this.modelTags,
    required this.modelConfidence,
    required this.bbox,
    required this.raw,
    required this.ttftMs,
    required this.wallclockMs,
  });

  final String observationId;
  final String promptId;
  final String askedIn;
  final List<String> imageRefs;
  final String modelDescription;
  final List<String> modelTags;
  final double modelConfidence;

  /// Raw JSON for `bbox_annotations` (kept opaque here; re-decoded by the
  /// session controller into typed `BBox` records when persisted).
  final List<Map<String, Object?>> bbox;
  final Map<String, Object?> raw;
  final int ttftMs;
  final int wallclockMs;
}

class AskFollowupResult {
  const AskFollowupResult({
    required this.followup,
    required this.targetObservationId,
    required this.askedIn,
    required this.raw,
  });

  final String followup;
  final String? targetObservationId;
  final String askedIn;
  final Map<String, Object?> raw;
}

class ProtocolAnswerResult {
  const ProtocolAnswerResult({required this.delta, required this.raw});

  /// Always exactly one entry per the system prompt contract.
  final MapEntry<String, Object?> delta;
  final Map<String, Object?> raw;
}

class SynthesizeResult {
  const SynthesizeResult({
    required this.rationaleBullets,
    required this.uncertaintyNotes,
    required this.recommendEngineerFollowup,
    required this.thinkingExcerpt,
    required this.raw,
  });

  final List<String> rationaleBullets;
  final List<String> uncertaintyNotes;
  final bool recommendEngineerFollowup;

  /// Whatever Gemma 4 emits inside the `<|think|>` block, if anything. For
  /// observability/UI display only — never persisted to the EvidencePacket.
  final String thinkingExcerpt;
  final Map<String, Object?> raw;
}

class GemmaOrchestrator {
  GemmaOrchestrator(this._session);

  final GemmaSession _session;

  /// Vision turn: ask Gemma to describe one photo against a P-154 prompt.
  Future<DescribePhotoResult> describePhoto({
    required String observationId,
    required String promptId,
    required String askedIn,
    required Uint8List imageBytes,
    required String imageRef,
    String? userText,
  }) async {
    final user = jsonEncode({
      'task': 'describe_photo',
      'observation_id': observationId,
      'prompt_id': promptId,
      'asked_in': askedIn,
      'image_refs': [imageRef],
      'audio_refs': <String>[],
      'user_text': userText,
    });
    final out = await _session.generate(userText: user, image: imageBytes);
    final parsed = extractFirstJsonObject(out.text);
    if (parsed == null) {
      throw GemmaContractError(
        'no JSON object in describe_photo response',
        rawText: out.text,
        task: 'describe_photo',
      );
    }
    final bbox =
        (parsed['bbox_annotations'] as List? ?? const []).cast<Map<String, Object?>>();
    return DescribePhotoResult(
      observationId: parsed['observation_id'] as String? ?? observationId,
      promptId: parsed['prompt_id'] as String? ?? promptId,
      askedIn: parsed['asked_in'] as String? ?? askedIn,
      imageRefs:
          (parsed['image_refs'] as List? ?? [imageRef]).cast<String>(),
      modelDescription:
          (parsed['model_description'] as String?)?.trim() ??
              (throw GemmaContractError(
                'missing model_description',
                rawText: out.text,
                task: 'describe_photo',
              )),
      modelTags:
          (parsed['model_tags'] as List? ?? const []).cast<String>(),
      modelConfidence:
          ((parsed['model_confidence'] as num?) ?? 0.5).toDouble(),
      bbox: bbox,
      raw: parsed,
      ttftMs: out.ttftMs,
      wallclockMs: out.wallclockMs,
    );
  }

  /// Humility-check turn: ask Gemma to formulate a follow-up question for the
  /// observation it was least confident about.
  Future<AskFollowupResult> askFollowup({
    required String askedIn,
    required Map<String, Object?>
        targetObservationSummary, // {observation_id, prompt_id, model_description, model_confidence}
  }) async {
    final user = jsonEncode({
      'task': 'ask_followup',
      'asked_in': askedIn,
      'target_observation': targetObservationSummary,
    });
    final out = await _session.generate(userText: user);
    final parsed = extractFirstJsonObject(out.text);
    if (parsed == null) {
      throw GemmaContractError(
        'no JSON object in ask_followup response',
        rawText: out.text,
        task: 'ask_followup',
      );
    }
    final f = parsed['followup'];
    if (f is! String || f.trim().isEmpty) {
      throw GemmaContractError(
        'missing or empty `followup` string',
        rawText: out.text,
        task: 'ask_followup',
      );
    }
    return AskFollowupResult(
      followup: f.trim(),
      targetObservationId:
          targetObservationSummary['observation_id'] as String?,
      askedIn: parsed['asked_in'] as String? ?? askedIn,
      raw: parsed,
    );
  }

  /// Map a free-text user response onto exactly one boolean / categorical
  /// `protocol_answers` field. The system prompt enforces `delta` has 1 key.
  Future<ProtocolAnswerResult> protocolAnswer({
    required String askedIn,
    required String questionId,
    required String userText,
  }) async {
    final user = jsonEncode({
      'task': 'protocol_answer',
      'asked_in': askedIn,
      'question_id': questionId,
      'user_text': userText,
    });
    final out = await _session.generate(userText: user);
    final parsed = extractFirstJsonObject(out.text);
    if (parsed == null) {
      throw GemmaContractError('no JSON object in protocol_answer',
          rawText: out.text, task: 'protocol_answer');
    }
    final delta = parsed['protocol_answers_delta'] as Map<String, Object?>?;
    if (delta == null || delta.length != 1) {
      throw GemmaContractError(
        'protocol_answers_delta must have exactly one key',
        rawText: out.text,
        task: 'protocol_answer',
      );
    }
    return ProtocolAnswerResult(
      delta: delta.entries.first,
      raw: parsed,
    );
  }

  /// Final synthesis (thinking mode). The orchestrator only collects the
  /// rationale + uncertainty bullets; the priority score is computed by Dart
  /// (`core/triage/priority.dart`) — never the LLM.
  Future<SynthesizeResult> synthesize({
    required String askedIn,
    required Map<String, Object?> packetSummary,
  }) async {
    final user = jsonEncode({
      'task': 'synthesize',
      'asked_in': askedIn,
      'packet_summary': packetSummary,
    });
    final out = await _session.generate(userText: user);
    final raw = out.text;
    final parsed = extractFirstJsonObject(raw);
    if (parsed == null) {
      throw GemmaContractError('no JSON object in synthesize response',
          rawText: raw, task: 'synthesize');
    }
    final draft = parsed['triage_draft'] as Map<String, Object?>?;
    if (draft == null) {
      throw GemmaContractError('missing triage_draft',
          rawText: raw, task: 'synthesize');
    }
    return SynthesizeResult(
      rationaleBullets:
          (draft['rationale_bullets'] as List? ?? const []).cast<String>(),
      uncertaintyNotes:
          (draft['uncertainty_notes'] as List? ?? const []).cast<String>(),
      recommendEngineerFollowup:
          draft['recommend_engineer_followup'] as bool? ?? true,
      // `ThinkingResponse` stream items are captured by `GemmaSession` into
      // its own buffer; we surface that directly rather than regex-scraping
      // the text (the text no longer contains `<|think|>` tags — MediaPipe
      // splits them into separate response events).
      thinkingExcerpt: out.thinking,
      raw: parsed,
    );
  }
}
