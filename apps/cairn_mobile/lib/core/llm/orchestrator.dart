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

import '../images/image_preprocessor.dart';
import '../models/evidence_packet_validator.dart';
import 'gemma_session.dart';
import 'json_extract.dart';
import 'turn_record.dart';

export 'turn_record.dart' show TurnRecord;

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
    required this.outputCharCount,
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

  /// Raw output character count from the session (text only, excluding
  /// thinking). Used by [GemmaOrchestrator.describeAll] to build [TurnRecord]s.
  final int outputCharCount;
}

class DescribePhotosBatchResult {
  const DescribePhotosBatchResult._({
    required this.results,
    required this.turns,
    required this.fallbackReason,
  });

  factory DescribePhotosBatchResult.success({
    required List<DescribePhotoResult> results,
    required List<TurnRecord> turns,
  }) =>
      DescribePhotosBatchResult._(
        results: results,
        turns: turns,
        fallbackReason: null,
      );

  factory DescribePhotosBatchResult.fallback(String reason) =>
      DescribePhotosBatchResult._(
        results: const [],
        turns: const [],
        fallbackReason: reason,
      );

  final List<DescribePhotoResult> results;
  final List<TurnRecord> turns;
  final String? fallbackReason;

  bool get shouldFallback => fallbackReason != null;
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

// ---------------------------------------------------------------------------
// Sprint 3 — describeAll stream types
// ---------------------------------------------------------------------------

/// Input for a single photo inference turn in [GemmaOrchestrator.describeAll].
///
/// Callers build one [DescribePhotoRequest] per captured slot and pass the
/// full list to [GemmaOrchestrator.describeAll]. The orchestrator owns:
/// - image preprocessing (via [ImagePreprocessor])
/// - the [GemmaSession.generate] call
/// - contract validation
/// - [TurnRecord] construction
///
/// Callers own: slot-status UI, retry logic, navigation.
class DescribePhotoRequest {
  const DescribePhotoRequest({
    required this.observationId,
    required this.promptId,
    required this.askedIn,
    required this.imageBytes,
    required this.imageRef,
    this.userText,
  });

  final String observationId;
  final String promptId;
  final String askedIn;

  /// Original capture bytes — the preprocessor receives these and may
  /// downscale before passing to the model.
  final Uint8List imageBytes;
  final String imageRef;
  final String? userText;
}

/// Events emitted by [GemmaOrchestrator.describeAll].
///
/// Use a `switch` on the sealed subclasses to handle all cases:
///
/// ```dart
/// await for (final event in orchestrator.describeAll(requests)) {
///   switch (event) {
///     case DescribePhotoStarted(:final index, :final total):
///       updateProgress(index, total);
///     case DescribePhotoSucceeded(:final result, :final turn):
///       controller.recordObservation(observationFrom(result));
///       controller.recordTurn(turn);
///     case DescribePhotoFailed(:final request, :final error):
///       showError(request.imageRef, error);
///   }
/// }
/// ```
sealed class DescribePhotoEvent {
  const DescribePhotoEvent();
}

/// Emitted immediately before the model call for photo at [index].
final class DescribePhotoStarted extends DescribePhotoEvent {
  const DescribePhotoStarted({
    required this.request,
    required this.index,
    required this.total,
  });

  final DescribePhotoRequest request;

  /// 0-based index of this photo in the batch.
  final int index;

  /// Total number of photos in this [GemmaOrchestrator.describeAll] call.
  final int total;
}

/// Emitted after the model returns a contract-valid response.
///
/// [turn] is already constructed; callers should pass it directly to
/// [SessionController.recordTurn] to guarantee provenance coverage without
/// needing to re-compute timing fields.
final class DescribePhotoSucceeded extends DescribePhotoEvent {
  const DescribePhotoSucceeded({
    required this.result,
    required this.turn,
  });

  final DescribePhotoResult result;

  /// Pre-built [TurnRecord] derived from [result]'s timing fields.
  final TurnRecord turn;
}

/// Emitted when preprocessing or the model call throws.
///
/// The error is isolated — [GemmaOrchestrator.describeAll] continues with
/// the next photo after emitting this event.
final class DescribePhotoFailed extends DescribePhotoEvent {
  const DescribePhotoFailed({
    required this.request,
    required this.error,
  });

  final DescribePhotoRequest request;
  final Object error;
}

/// Allowed keys for `protocol_answers_delta` in a `protocol_answer` turn.
///
/// Must stay in sync with [SessionController.applyProtocolDelta] and the
/// `protocol_answers` schema in `evidence_packet_v1.schema.json`.
const _kAllowedProtocolKeys = {
  'visible_collapse',
  'building_off_foundation',
  'leaning',
  'ground_failure_adjacent',
  'falling_hazards',
  'adjacent_leaning',
};

class GemmaOrchestrator {
  GemmaOrchestrator(
    this._session, {
    ImagePreprocessor preprocessor = const PassthroughImagePreprocessor(),
    bool enableBatchVision = false,
  })  : _preprocessor = preprocessor,
        _enableBatchVision = enableBatchVision;

  /// Accepts [GemmaSessionInterface] so tests can supply a fake without
  /// instantiating a real model.
  final GemmaSessionInterface _session;

  /// Image preprocessor used on the inference path in [describePhoto] and
  /// [describeAll]. Capture bytes in [SessionDraft.photos] are never modified.
  final ImagePreprocessor _preprocessor;
  final bool _enableBatchVision;

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
    final inferenceBytes = await _preprocessor.prepareForInference(imageBytes);
    final out = await _session.generate(userText: user, image: inferenceBytes);
    final parsed = _parseTaskObject(
      out,
      task: 'describe_photo',
      expectedToolName: 'describe_photo',
    );
    return _describePhotoResultFromParsed(
      parsed,
      rawText: out.text,
      observationId: observationId,
      promptId: promptId,
      askedIn: askedIn,
      imageRef: imageRef,
      ttftMs: out.ttftMs,
      wallclockMs: out.wallclockMs,
      outputCharCount: out.outputCharCount,
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
      'task': 'describe_audio',
      'observation_id': observationId,
      'prompt_id': promptId,
      'asked_in': askedIn,
      'image_refs': <String>[],
      'audio_refs': [audioRef],
      'user_text': userText,
    });
    final out = await _session.generate(userText: user, audioBytes: audioBytes);
    final parsed = _parseTaskObject(out, task: 'describe_audio');

    final tags = (parsed['model_tags'] as List? ?? const []).cast<String>();
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
      audioRefs: _expectedRefs(
        parsed,
        field: 'audio_refs',
        expectedRef: audioRef,
        rawText: out.text,
        task: 'describe_audio',
      ),
      modelDescription: (parsed['model_description'] as String?)?.trim() ??
          (throw GemmaContractError(
            'missing model_description',
            rawText: out.text,
            task: 'describe_audio',
          )),
      modelTags: tags,
      modelConfidence:
          _modelConfidence(parsed, rawText: out.text, task: 'describe_audio'),
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
    final parsed = _parseTaskObject(
      out,
      task: 'ask_followup',
      expectedToolName: 'ask_followup',
    );

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
    final parsed = _parseTaskObject(
      out,
      task: 'protocol_answer',
      expectedToolName: 'protocol_answer',
    );
    final delta = parsed['protocol_answers_delta'] as Map<String, Object?>?;
    if (delta == null || delta.length != 1) {
      throw GemmaContractError(
        'protocol_answers_delta must have exactly one key',
        rawText: out.text,
        task: 'protocol_answer',
      );
    }
    final deltaKey = delta.keys.first;
    if (!_kAllowedProtocolKeys.contains(deltaKey)) {
      throw GemmaContractError(
        'protocol_answer: delta key "$deltaKey" is not a valid '
        'protocol_answers field',
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

  /// Describe a batch of photos sequentially, emitting [DescribePhotoEvent]s.
  ///
  /// The orchestrator owns the full per-photo lifecycle:
  ///   1. Emit [DescribePhotoStarted] (UI: set slot to "describing").
  ///   2. Preprocess [DescribePhotoRequest.imageBytes] via [_preprocessor].
  ///   3. Call [describePhoto] (model inference + contract validation).
  ///   4. On success: emit [DescribePhotoSucceeded] with a ready [TurnRecord].
  ///   5. On any error: emit [DescribePhotoFailed] and continue to next photo.
  ///      Errors are isolated — one bad photo never aborts the batch.
  ///
  /// The caller (UI) is responsible for:
  ///   - Updating slot status based on events.
  ///   - Calling [SessionController.recordObservation] with the result.
  ///   - Calling [SessionController.recordTurn] with the [TurnRecord].
  ///   - Providing retry buttons for failed slots.
  ///
  /// Example:
  /// ```dart
  /// await for (final event in orch.describeAll(requests)) {
  ///   switch (event) {
  ///     case DescribePhotoStarted(:final index, :final total, :final request):
  ///       setState(() { _setSlotDescribing(request.imageRef); });
  ///     case DescribePhotoSucceeded(:final result, :final turn):
  ///       controller.recordObservation(observationFrom(result));
  ///       controller.recordTurn(turn);
  ///       setState(() { _setSlotDone(result.imageRefs.first); });
  ///     case DescribePhotoFailed(:final request, :final error):
  ///       setState(() { _setSlotError(request.imageRef, error); });
  ///   }
  /// }
  /// ```
  Stream<DescribePhotoEvent> describeAll(
      List<DescribePhotoRequest> photos) async* {
    if (_enableBatchVision && photos.length > 1) {
      for (var i = 0; i < photos.length; i++) {
        yield DescribePhotoStarted(
          request: photos[i],
          index: i,
          total: photos.length,
        );
      }
      final batch = await describePhotosBatch(photos);
      if (!batch.shouldFallback) {
        for (var i = 0; i < batch.results.length; i++) {
          yield DescribePhotoSucceeded(
            result: batch.results[i],
            turn: batch.turns[i],
          );
        }
        return;
      }
    }

    for (var i = 0; i < photos.length; i++) {
      final req = photos[i];
      yield DescribePhotoStarted(request: req, index: i, total: photos.length);
      final ts = DateTime.now().toUtc();
      try {
        final result = await describePhoto(
          observationId: req.observationId,
          promptId: req.promptId,
          askedIn: req.askedIn,
          imageBytes: req.imageBytes,
          imageRef: req.imageRef,
          userText: req.userText,
        );
        final turn = TurnRecord(
          ts: ts,
          task: 'describe_photo',
          observationId: req.observationId,
          ttftMs: result.ttftMs,
          wallclockMs: result.wallclockMs,
          outputCharCount: result.outputCharCount,
        );
        yield DescribePhotoSucceeded(result: result, turn: turn);
      } catch (e) {
        yield DescribePhotoFailed(request: req, error: e);
      }
    }
  }

  Future<DescribePhotosBatchResult> describePhotosBatch(
      List<DescribePhotoRequest> photos) async {
    if (photos.isEmpty) {
      return DescribePhotosBatchResult.success(
          results: const [], turns: const []);
    }
    final batchSession = _session is BatchGemmaSessionInterface
        ? _session as BatchGemmaSessionInterface
        : null;
    if (batchSession == null) {
      return DescribePhotosBatchResult.fallback(
          'session does not support batch');
    }

    try {
      final inferenceBytes = <Uint8List>[];
      for (final req in photos) {
        inferenceBytes
            .add(await _preprocessor.prepareForInference(req.imageBytes));
      }
      final user = jsonEncode({
        'task': 'describe_photos_batch',
        'photos': [
          for (final req in photos)
            {
              'observation_id': req.observationId,
              'prompt_id': req.promptId,
              'asked_in': req.askedIn,
              'image_refs': [req.imageRef],
              'audio_refs': <String>[],
              'user_text': req.userText,
            },
        ],
      });
      final ts = DateTime.now().toUtc();
      final out = await batchSession.generateBatch(
        userText: user,
        images: inferenceBytes,
      );
      final parsed = _parseTaskObject(out, task: 'describe_photos_batch');
      final rawObservations = parsed['observations'] as List?;
      if (rawObservations == null || rawObservations.length != photos.length) {
        return DescribePhotosBatchResult.fallback(
          'batch returned ${rawObservations?.length ?? 0} observations for '
          '${photos.length} requests',
        );
      }

      final results = <DescribePhotoResult>[];
      final turns = <TurnRecord>[];
      for (var i = 0; i < photos.length; i++) {
        final item = rawObservations[i];
        if (item is! Map) {
          return DescribePhotosBatchResult.fallback(
            'batch observation $i is ${item.runtimeType}, expected object',
          );
        }
        final req = photos[i];
        final parsedItem = Map<String, Object?>.from(item);
        final result = _describePhotoResultFromParsed(
          parsedItem,
          rawText: out.text,
          observationId: req.observationId,
          promptId: req.promptId,
          askedIn: req.askedIn,
          imageRef: req.imageRef,
          ttftMs: out.ttftMs,
          wallclockMs: out.wallclockMs,
          outputCharCount: out.outputCharCount,
        );
        final returnedRef =
            result.imageRefs.isEmpty ? null : result.imageRefs.first;
        if (returnedRef != req.imageRef) {
          return DescribePhotosBatchResult.fallback(
            'batch observation $i image_ref mismatch: $returnedRef != '
            '${req.imageRef}',
          );
        }
        results.add(result);
        turns.add(TurnRecord(
          ts: ts,
          task: 'describe_photo',
          observationId: req.observationId,
          ttftMs: out.ttftMs,
          wallclockMs: out.wallclockMs,
          outputCharCount: out.outputCharCount,
        ));
      }
      return DescribePhotosBatchResult.success(results: results, turns: turns);
    } catch (e) {
      return DescribePhotosBatchResult.fallback(e.toString());
    }
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
    final parsed = _parseTaskObject(
      out,
      task: 'synthesize',
      expectedToolName: 'synthesize',
    );
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

  Map<String, Object?> _parseTaskObject(
    GemmaInferenceResult out, {
    required String task,
    String? expectedToolName,
  }) {
    if (expectedToolName != null) {
      GemmaToolCall? matching;
      for (final call in out.toolCalls) {
        if (call.name == expectedToolName) {
          matching = call;
          break;
        }
      }
      if (matching != null) return matching.args;
      if (out.runtimeName == GemmaSession.runtimeName) {
        // The model occasionally emits a bare JSON TextResponse even with
        // ToolChoice.required. Try the text fallback before throwing.
        final fallback = extractFirstJsonObject(out.text);
        if (fallback != null) return fallback;
        throw GemmaContractError(
          'required tool call "$expectedToolName" missing',
          rawText: out.text,
          task: task,
        );
      }
    }
    final parsed = extractFirstJsonObject(out.text);
    if (parsed == null) {
      throw GemmaContractError(
        'no JSON object in $task response',
        rawText: out.text,
        task: task,
      );
    }
    return parsed;
  }

  DescribePhotoResult _describePhotoResultFromParsed(
    Map<String, Object?> parsed, {
    required String rawText,
    required String observationId,
    required String promptId,
    required String askedIn,
    required String imageRef,
    required int ttftMs,
    required int wallclockMs,
    required int outputCharCount,
  }) {
    final imageRefs = _expectedRefs(
      parsed,
      field: 'image_refs',
      expectedRef: imageRef,
      rawText: rawText,
      task: 'describe_photo',
    );
    final tags = (parsed['model_tags'] as List? ?? const []).cast<String>();
    for (final tag in tags) {
      if (!EvidencePacketValidator.kAllowedModelTags.contains(tag)) {
        throw GemmaContractError(
          'describe_photo: model_tags contains unknown tag "$tag"',
          rawText: rawText,
          task: 'describe_photo',
        );
      }
    }

    final bbox = [
      for (final item in (parsed['bbox_annotations'] as List? ?? const []))
        Map<String, Object?>.from(item as Map),
    ];
    for (var i = 0; i < bbox.length; i++) {
      final b = bbox[i];
      final bboxImageRef = b['image_ref'] as String?;
      if (bboxImageRef == null) {
        b['image_ref'] = imageRef;
      } else if (bboxImageRef != imageRef) {
        throw GemmaContractError(
          'describe_photo: bbox_annotations[$i].image_ref "$bboxImageRef" '
          'does not match request image_ref "$imageRef"',
          rawText: rawText,
          task: 'describe_photo',
        );
      }
      final box2d = (b['box_2d'] as List?)?.cast<num>().toList();
      if (box2d == null || box2d.length != 4) {
        throw GemmaContractError(
          'describe_photo: bbox_annotations[$i].box_2d must have exactly 4 '
          'elements [y1,x1,y2,x2]',
          rawText: rawText,
          task: 'describe_photo',
        );
      }
      for (final v in box2d) {
        if (v < 0 || v > 1000) {
          throw GemmaContractError(
            'describe_photo: bbox_annotations[$i].box_2d value $v is outside '
            '0..1000',
            rawText: rawText,
            task: 'describe_photo',
          );
        }
      }
      if (box2d[0] >= box2d[2]) {
        throw GemmaContractError(
          'describe_photo: bbox_annotations[$i].box_2d y1 (${box2d[0]}) '
          'must be < y2 (${box2d[2]})',
          rawText: rawText,
          task: 'describe_photo',
        );
      }
      if (box2d[1] >= box2d[3]) {
        throw GemmaContractError(
          'describe_photo: bbox_annotations[$i].box_2d x1 (${box2d[1]}) '
          'must be < x2 (${box2d[3]})',
          rawText: rawText,
          task: 'describe_photo',
        );
      }
    }

    return DescribePhotoResult(
      observationId: parsed['observation_id'] as String? ?? observationId,
      promptId: parsed['prompt_id'] as String? ?? promptId,
      askedIn: parsed['asked_in'] as String? ?? askedIn,
      imageRefs: imageRefs,
      modelDescription: (parsed['model_description'] as String?)?.trim() ??
          (throw GemmaContractError(
            'missing model_description',
            rawText: rawText,
            task: 'describe_photo',
          )),
      modelTags: tags,
      modelConfidence:
          _modelConfidence(parsed, rawText: rawText, task: 'describe_photo'),
      bbox: bbox,
      raw: parsed,
      ttftMs: ttftMs,
      wallclockMs: wallclockMs,
      outputCharCount: outputCharCount,
    );
  }

  List<String> _expectedRefs(
    Map<String, Object?> parsed, {
    required String field,
    required String expectedRef,
    required String rawText,
    required String task,
  }) {
    final rawRefs = parsed[field];
    if (rawRefs == null) return [expectedRef];
    if (rawRefs is! List) {
      throw GemmaContractError(
        '$task: $field must be an array',
        rawText: rawText,
        task: task,
      );
    }
    final refs = rawRefs.cast<String>();
    if (refs.length != 1 || refs.first != expectedRef) {
      throw GemmaContractError(
        '$task: $field must contain exactly "$expectedRef", got $refs',
        rawText: rawText,
        task: task,
      );
    }
    return refs;
  }

  double _modelConfidence(
    Map<String, Object?> parsed, {
    required String rawText,
    required String task,
  }) {
    final rawConfidence = parsed['model_confidence'];
    if (rawConfidence is! num) {
      throw GemmaContractError(
        '$task: model_confidence must be a number in 0..1',
        rawText: rawText,
        task: task,
      );
    }
    final confidence = rawConfidence.toDouble();
    if (confidence < 0 || confidence > 1) {
      throw GemmaContractError(
        '$task: model_confidence $confidence is outside 0..1',
        rawText: rawText,
        task: task,
      );
    }
    return confidence;
  }
}
