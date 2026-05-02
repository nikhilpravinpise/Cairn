/// LLM orchestrator — the only place that builds user-turn JSON for Gemma.
///
/// Implements the four task contracts from the locked system prompt:
///   * describe_photo
///   * ask_followup
///   * protocol_answer
///   * synthesize
///
/// Phase 6 additions:
///   * describe_audio (audio bytes via Message.withAudio)
///   * Contract enforcement: model_tags enum check, bbox coord validation,
///     priority_score/band rejection in synthesize
///
/// Fails loud on parse / contract violations. The session controller decides
/// whether to surface the error or re-ask the model.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/evidence_packet_validator.dart';
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

/// One run of `describe_audio`.
class DescribeAudioResult {
  const DescribeAudioResult({
    required this.observationId,
    required this.promptId,
    required this.askedIn,
    required this.audioRefs,
    required this.modelDescription,
    required this.modelTags,
    required this.modelConfidence,
    required this.raw,
    required this.ttftMs,
    required this.wallclockMs,
  });

  final String observationId;
  final String promptId;
  final String askedIn;
  final List<String> audioRefs;
  final String modelDescription;
  final List<String> modelTags;
  final double modelConfidence;
  final Map<String, Object?> raw;
  final int ttftMs;
  final int wallclockMs;
}

class AskFollowupResult {
  const AskFollowupResult({
    this.question,
    this.targetObservationId,
    required this.askedIn,
    required this.raw,
    required this.ttftMs,
    required this.wallclockMs,
  });

  /// The follow-up question to pose to the volunteer.
  /// `null` means the model determined no follow-up is needed
  /// (`{ "followup": null }` per system prompt §TURN TYPES).
  final String? question;
  final String? targetObservationId;
  final String askedIn;
  final Map<String, Object?> raw;
  final int ttftMs;
  final int wallclockMs;

  bool get hasFollowup => question != null;
}

class ProtocolAnswerResult {
  const ProtocolAnswerResult({
    required this.delta,
    required this.raw,
    required this.ttftMs,
    required this.wallclockMs,
  });

  /// Always exactly one entry per the system prompt contract.
  final MapEntry<String, Object?> delta;
  final Map<String, Object?> raw;
  final int ttftMs;
  final int wallclockMs;
}

class SynthesizeResult {
  const SynthesizeResult({
    required this.rationaleBullets,
    required this.uncertaintyNotes,
    required this.recommendEngineerFollowup,
    required this.thinkingExcerpt,
    required this.raw,
    required this.ttftMs,
    required this.wallclockMs,
  });

  final List<String> rationaleBullets;
  final List<String> uncertaintyNotes;
  final bool recommendEngineerFollowup;

  /// Whatever Gemma 4 emits inside the `<|think|>` block, if anything. For
  /// observability/UI display only — never persisted to the EvidencePacket.
  final String thinkingExcerpt;
  final Map<String, Object?> raw;
  final int ttftMs;
  final int wallclockMs;
}

class GemmaOrchestrator {
  GemmaOrchestrator(this._session);

  /// Accepts [GemmaSessionInterface] so tests can supply a fake without
  /// instantiating a real model.
  final GemmaSessionInterface _session;

  /// Vision turn: ask Gemma to describe one photo against a P-154 prompt.
  ///
  /// Contract checks (Phase 6):
  /// - Each tag in `model_tags` must be in [EvidencePacketValidator.kAllowedModelTags].
  /// - Each `bbox_annotations` entry must have `box_2d` with exactly 4 integers
  ///   in 0..1000 (Gemma vision convention: [y1, x1, y2, x2]).
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

    final tags =
        (parsed['model_tags'] as List? ?? const []).cast<String>();
    for (final tag in tags) {
      if (!EvidencePacketValidator.kAllowedModelTags.contains(tag)) {
        throw GemmaContractError(
          'describe_photo: model_tags contains unknown tag "$tag"',
          rawText: out.text,
          task: 'describe_photo',
        );
      }
    }

    final bbox =
        (parsed['bbox_annotations'] as List? ?? const [])
            .cast<Map<String, Object?>>();
    for (var i = 0; i < bbox.length; i++) {
      final b = bbox[i];
      final box2d = (b['box_2d'] as List?)?.cast<num>().toList();
      if (box2d == null || box2d.length != 4) {
        throw GemmaContractError(
          'describe_photo: bbox_annotations[$i].box_2d must have exactly 4 '
          'elements [y1,x1,y2,x2]',
          rawText: out.text,
          task: 'describe_photo',
        );
      }
      for (final v in box2d) {
        if (v < 0 || v > 1000) {
          throw GemmaContractError(
            'describe_photo: bbox_annotations[$i].box_2d value $v is outside '
            '0..1000',
            rawText: out.text,
            task: 'describe_photo',
          );
        }
      }
    }

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
      modelTags: tags,
      modelConfidence:
          ((parsed['model_confidence'] as num?) ?? 0.5).toDouble(),
      bbox: bbox,
      raw: parsed,
      ttftMs: out.ttftMs,
      wallclockMs: out.wallclockMs,
    );
  }

  /// Audio turn: ask Gemma to describe one audio clip against a P-154 prompt.
  ///
  /// Requires a session opened with `supportAudio: true`
  /// ([GemmaSession.openForAudio]). Sends audio bytes via
  /// [Message.withAudio]. Applies the same tag contract check as
  /// [describePhoto].
  Future<DescribeAudioResult> describeAudio({
    required String observationId,
    required String promptId,
    required String askedIn,
    required Uint8List audioBytes,
    required String audioRef,
    String? userText,
  }) async {
    final user = jsonEncode({
      'task': 'describe_photo',
      'observation_id': observationId,
      'prompt_id': promptId,
      'asked_in': askedIn,
      'image_refs': <String>[],
      'audio_refs': [audioRef],
      'user_text': userText,
    });
    final out =
        await _session.generate(userText: user, audioBytes: audioBytes);
    final parsed = extractFirstJsonObject(out.text);
    if (parsed == null) {
      throw GemmaContractError(
        'no JSON object in describe_audio response',
        rawText: out.text,
        task: 'describe_audio',
      );
    }

    final tags =
        (parsed['model_tags'] as List? ?? const []).cast<String>();
    for (final tag in tags) {
      if (!EvidencePacketValidator.kAllowedModelTags.contains(tag)) {
        throw GemmaContractError(
          'describe_audio: model_tags contains unknown tag "$tag"',
          rawText: out.text,
          task: 'describe_audio',
        );
      }
    }

    return DescribeAudioResult(
      observationId: parsed['observation_id'] as String? ?? observationId,
      promptId: parsed['prompt_id'] as String? ?? promptId,
      askedIn: parsed['asked_in'] as String? ?? askedIn,
      audioRefs: (parsed['audio_refs'] as List? ?? [audioRef]).cast<String>(),
      modelDescription:
          (parsed['model_description'] as String?)?.trim() ??
              (throw GemmaContractError(
                'missing model_description',
                rawText: out.text,
                task: 'describe_audio',
              )),
      modelTags: tags,
      modelConfidence:
          ((parsed['model_confidence'] as num?) ?? 0.5).toDouble(),
      raw: parsed,
      ttftMs: out.ttftMs,
      wallclockMs: out.wallclockMs,
    );
  }

  /// Humility-check turn: ask Gemma to formulate a follow-up question for the
  /// observation it was least confident about.
  ///
  /// Per the system prompt §TURN TYPES, the model may return
  /// `{ "followup": null }` when all observations are already high-confidence.
  /// In that case [AskFollowupResult.hasFollowup] is `false` and the caller
  /// should skip displaying a question.
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
    String? question;
    String? targetObservationId;

    if (f == null) {
      // Model says no follow-up is needed; question stays null.
    } else if (f is Map<String, Object?>) {
      final q = f['question'] as String?;
      if (q == null || q.trim().isEmpty) {
        throw GemmaContractError(
          'ask_followup: followup dict must contain a non-empty "question" string',
          rawText: out.text,
          task: 'ask_followup',
        );
      }
      question = q.trim();
      targetObservationId = f['target_observation_id'] as String?;
    } else {
      throw GemmaContractError(
        'ask_followup: "followup" must be null or an object with '
        '"target_observation_id" and "question", got ${f.runtimeType}',
        rawText: out.text,
        task: 'ask_followup',
      );
    }

    return AskFollowupResult(
      question: question,
      targetObservationId: targetObservationId,
      askedIn: parsed['asked_in'] as String? ?? askedIn,
      raw: parsed,
      ttftMs: out.ttftMs,
      wallclockMs: out.wallclockMs,
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
      ttftMs: out.ttftMs,
      wallclockMs: out.wallclockMs,
    );
  }

  /// Final synthesis (thinking mode). The orchestrator only collects the
  /// rationale + uncertainty bullets; the priority score is computed by Dart
  /// (`core/triage/priority.dart`) — never the LLM.
  ///
  /// Contract check (Phase 6): throws [GemmaContractError] if the model
  /// supplies `priority_score` or `priority_band` — those fields are computed
  /// exclusively by the app (system prompt §HARD RULES rule 8).
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
    if (draft.containsKey('priority_score')) {
      throw GemmaContractError(
        'synthesize: model must not set priority_score — the app computes it '
        '(system prompt rule 8)',
        rawText: raw,
        task: 'synthesize',
      );
    }
    if (draft.containsKey('priority_band')) {
      throw GemmaContractError(
        'synthesize: model must not set priority_band — the app computes it '
        '(system prompt rule 8)',
        rawText: raw,
        task: 'synthesize',
      );
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
      ttftMs: out.ttftMs,
      wallclockMs: out.wallclockMs,
    );
  }
}
