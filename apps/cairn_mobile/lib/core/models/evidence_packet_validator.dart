/// Schema-safety validator for sealed `EvidencePacket` objects.
///
/// Mirrors `docs/schema/evidence_packet_v1.schema.json` in Dart so the app
/// can gate the Report screen on a valid packet without a separate JSON Schema
/// library.  Intentionally a pure-function utility (no state, no Flutter) so
/// it can be exercised in vanilla Dart tests.
///
/// Usage:
///   ```dart
///   final errors = EvidencePacketValidator.validate(packet);
///   if (errors.isNotEmpty) throw SchemaValidationException(errors);
///   ```
library;

import 'evidence_packet.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// A single schema constraint violation.
class ValidationError {
  const ValidationError({required this.path, required this.message});

  /// JSON-pointer-style path, e.g. `observations[2].model_tags[0]`.
  final String path;
  final String message;

  @override
  String toString() => '[$path] $message';
}

/// Thrown by [EvidencePacketValidator.validateOrThrow] when one or more
/// [ValidationError]s are found.
class SchemaValidationException implements Exception {
  const SchemaValidationException(this.errors);

  final List<ValidationError> errors;

  @override
  String toString() =>
      'SchemaValidationException (${errors.length} error(s)):\n'
      '${errors.map((e) => '  $e').join('\n')}';
}

/// Stateless validator.  All members are static.
class EvidencePacketValidator {
  EvidencePacketValidator._();

  // ---------------------------------------------------------------------------
  // Closed enumerations from the schema
  // ---------------------------------------------------------------------------

  static const Set<String> kAllowedModelTags = {
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
  };

  static const Set<String> kAllowedPriorityBands = {
    'LOW',
    'MEDIUM',
    'HIGH',
    'CRITICAL',
  };

  static const Set<String> kAllowedLeaningValues = {
    'none',
    'slight',
    'moderate',
    'severe',
  };

  static const Set<String> kAllowedBuildingTypes = {
    'concrete_moment_frame',
    'unreinforced_masonry',
    'wood_light_frame',
    'steel',
    'mixed',
    'unknown',
  };

  static const Set<String> kAllowedQuants = {
    'int4',
    'int8',
    'fp16',
    'fp32',
    'bf16',
  };

  static const Set<String> kAllowedAskedIn = {'en', 'es', 'tr'};

  // ---------------------------------------------------------------------------
  // Compiled regexes
  // ---------------------------------------------------------------------------

  static final _obsIdRe = RegExp(r'^obs-[0-9]+$');
  static final _imgRefRe = RegExp(r'^img-[0-9]+$');
  static final _audRefRe = RegExp(r'^aud-[0-9]+$');
  static final _sha256Re = RegExp(r'^[0-9a-f]{64}$');
  static final _sigHashRe = RegExp(r'^sha256:[0-9a-f]{64}$');
  static final _uuidv7Re = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
  static final _appVersionRe =
      RegExp(r'^\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$');
  static final _localeRe = RegExp(r'^(en|es|tr)(-[A-Z]{2})?$');

  // ---------------------------------------------------------------------------
  // Entry points
  // ---------------------------------------------------------------------------

  /// Returns all validation errors found in [packet].  Empty list = valid.
  static List<ValidationError> validate(EvidencePacket packet) {
    final errors = <ValidationError>[];
    _checkTopLevel(packet, errors);
    _checkModel(packet, errors);
    _checkLocation(packet, errors);
    _checkBuilding(packet, errors);
    _checkObservations(packet, errors);
    _checkHazards(packet, errors);
    _checkProtocolAnswers(packet, errors);
    _checkTriage(packet, errors);
    _checkVolunteer(packet, errors);
    _checkAssets(packet, errors);
    return errors;
  }

  /// Validates [packet] and throws [SchemaValidationException] if invalid.
  static void validateOrThrow(EvidencePacket packet) {
    final errors = validate(packet);
    if (errors.isNotEmpty) throw SchemaValidationException(errors);
  }

  // ---------------------------------------------------------------------------
  // Internal sections
  // ---------------------------------------------------------------------------

  static void _checkTopLevel(
      EvidencePacket p, List<ValidationError> errors) {
    if (!_uuidv7Re.hasMatch(p.packetId)) {
      errors.add(ValidationError(
          path: 'packet_id',
          message:
              'must match UUIDv7 pattern, got "${p.packetId}"'));
    }
    if (!_appVersionRe.hasMatch(p.appVersion)) {
      errors.add(ValidationError(
          path: 'app_version',
          message:
              'must match semver pattern, got "${p.appVersion}"'));
    }
    if (p.protocol != 'FEMA-P-154-L1') {
      errors.add(ValidationError(
          path: 'protocol',
          message: 'must be "FEMA-P-154-L1", got "${p.protocol}"'));
    }
  }

  static void _checkModel(EvidencePacket p, List<ValidationError> errors) {
    if (!kAllowedQuants.contains(p.modelQuant)) {
      errors.add(ValidationError(
          path: 'model.quant',
          message:
              '"${p.modelQuant}" is not one of ${kAllowedQuants.join(', ')}'));
    }
    if (p.modelName.isEmpty) {
      errors.add(const ValidationError(
          path: 'model.name', message: 'must be non-empty'));
    }
  }

  static void _checkLocation(
      EvidencePacket p, List<ValidationError> errors) {
    final loc = p.location;
    if (loc.lat < -90 || loc.lat > 90) {
      errors.add(ValidationError(
          path: 'location.lat',
          message: 'must be -90..90, got ${loc.lat}'));
    }
    if (loc.lng < -180 || loc.lng > 180) {
      errors.add(ValidationError(
          path: 'location.lng',
          message: 'must be -180..180, got ${loc.lng}'));
    }
    if (loc.accuracyMeters < 0) {
      errors.add(ValidationError(
          path: 'location.accuracy_m',
          message: 'must be >= 0, got ${loc.accuracyMeters}'));
    }
  }

  static void _checkBuilding(
      EvidencePacket p, List<ValidationError> errors) {
    final b = p.building;
    if (!kAllowedBuildingTypes.contains(b.type)) {
      errors.add(ValidationError(
          path: 'building.type',
          message:
              '"${b.type}" is not a recognised building type'));
    }
    if (b.storiesAboveGrade < 0 || b.storiesAboveGrade > 200) {
      errors.add(ValidationError(
          path: 'building.stories_above_grade',
          message:
              'must be 0..200, got ${b.storiesAboveGrade}'));
    }
    final y = b.yearBuiltEst;
    if (y != null && (y < 1700 || y > 2100)) {
      errors.add(ValidationError(
          path: 'building.year_built_est',
          message: 'must be 1700..2100, got $y'));
    }
  }

  static void _checkObservations(
      EvidencePacket p, List<ValidationError> errors) {
    final obs = p.observations;
    final imageRefs = {for (final i in p.images) i.ref};
    final audioRefs = {for (final a in p.audio) a.ref};

    if (obs.length > 16) {
      errors.add(ValidationError(
          path: 'observations',
          message: 'maxItems is 16, got ${obs.length}'));
    }

    for (var i = 0; i < obs.length; i++) {
      final o = obs[i];
      final pfx = 'observations[$i]';

      if (!_obsIdRe.hasMatch(o.observationId)) {
        errors.add(ValidationError(
            path: '$pfx.observation_id',
            message:
                'must match ^obs-[0-9]+\$, got "${o.observationId}"'));
      }
      if (o.promptId.isEmpty) {
        errors.add(ValidationError(
            path: '$pfx.prompt_id', message: 'must be non-empty'));
      }
      if (!kAllowedAskedIn.contains(o.askedIn)) {
        errors.add(ValidationError(
            path: '$pfx.asked_in',
            message:
                '"${o.askedIn}" must be one of ${kAllowedAskedIn.join(', ')}'));
      }

      for (var ti = 0; ti < o.modelTags.length; ti++) {
        final tag = o.modelTags[ti];
        if (!kAllowedModelTags.contains(tag)) {
          errors.add(ValidationError(
              path: '$pfx.model_tags[$ti]',
              message: '"$tag" is not in the schema model_tags enum'));
        }
      }

      for (var ri = 0; ri < o.imageRefs.length; ri++) {
        final ref = o.imageRefs[ri];
        if (!_imgRefRe.hasMatch(ref)) {
          errors.add(ValidationError(
              path: '$pfx.image_refs[$ri]',
              message: 'must match ^img-[0-9]+\$, got "$ref"'));
        } else if (!imageRefs.contains(ref)) {
          errors.add(ValidationError(
              path: '$pfx.image_refs[$ri]',
              message: '"$ref" not found in assets.images'));
        }
      }

      for (var ai = 0; ai < o.audioRefs.length; ai++) {
        final ref = o.audioRefs[ai];
        if (!_audRefRe.hasMatch(ref)) {
          errors.add(ValidationError(
              path: '$pfx.audio_refs[$ai]',
              message: 'must match ^aud-[0-9]+\$, got "$ref"'));
        } else if (!audioRefs.contains(ref)) {
          errors.add(ValidationError(
              path: '$pfx.audio_refs[$ai]',
              message: '"$ref" not found in assets.audio'));
        }
      }

      _checkBbox(o, pfx, imageRefs, errors);
    }
  }

  static void _checkBbox(
    Observation o,
    String pfx,
    Set<String> imageRefs,
    List<ValidationError> errors,
  ) {
    for (var bi = 0; bi < o.bboxAnnotations.length; bi++) {
      final b = o.bboxAnnotations[bi];
      final bpfx = '$pfx.bbox_annotations[$bi]';

      if (!imageRefs.contains(b.imageRef)) {
        errors.add(ValidationError(
            path: '$bpfx.image_ref',
            message:
                '"${b.imageRef}" not found in assets.images'));
      }
      if (b.box2d.length != 4) {
        errors.add(ValidationError(
            path: '$bpfx.box_2d',
            message:
                'must have exactly 4 elements [y1,x1,y2,x2], got ${b.box2d.length}'));
      } else {
        for (var ci = 0; ci < 4; ci++) {
          final v = b.box2d[ci];
          if (v < 0 || v > 1000) {
            errors.add(ValidationError(
                path: '$bpfx.box_2d[$ci]',
                message: 'must be 0..1000, got $v'));
          }
        }
      }
      if (b.label.isEmpty) {
        errors.add(ValidationError(
            path: '$bpfx.label', message: 'must be non-empty'));
      }
    }
  }

  static void _checkHazards(
      EvidencePacket p, List<ValidationError> errors) {
    const allowedCodes = {
      'H01_soft_story',
      'H02_unreinforced_masonry',
      'H03_pounding',
      'H04_falling_hazard',
      'H05_adjacent_leaning',
      'H06_ground_failure',
      'H07_chimney_parapet',
      'H08_foundation_displacement',
    };
    const allowedSeverity = {'low', 'moderate', 'high'};

    for (var i = 0; i < p.hazardsFlagged.length; i++) {
      final h = p.hazardsFlagged[i];
      final pfx = 'hazards_flagged[$i]';
      if (!allowedCodes.contains(h.code)) {
        errors.add(ValidationError(
            path: '$pfx.code',
            message: '"${h.code}" is not a recognised hazard code'));
      }
      if (!allowedSeverity.contains(h.severity)) {
        errors.add(ValidationError(
            path: '$pfx.severity',
            message:
                '"${h.severity}" must be one of low, moderate, high'));
      }
    }
  }

  static void _checkProtocolAnswers(
      EvidencePacket p, List<ValidationError> errors) {
    final pa = p.protocolAnswers;
    if (!kAllowedLeaningValues.contains(pa.leaning)) {
      errors.add(ValidationError(
          path: 'protocol_answers.leaning',
          message:
              '"${pa.leaning}" must be one of ${kAllowedLeaningValues.join(', ')}'));
    }
  }

  static void _checkTriage(EvidencePacket p, List<ValidationError> errors) {
    final t = p.triage;
    if (t.priorityScore < 1 || t.priorityScore > 10) {
      errors.add(ValidationError(
          path: 'triage.priority_score',
          message: 'must be 1..10, got ${t.priorityScore}'));
    }
    if (!kAllowedPriorityBands.contains(t.priorityBand)) {
      errors.add(ValidationError(
          path: 'triage.priority_band',
          message:
              '"${t.priorityBand}" must be one of ${kAllowedPriorityBands.join(', ')}'));
    }
    if (t.rationaleBullets.isEmpty) {
      errors.add(const ValidationError(
          path: 'triage.rationale_bullets',
          message: 'minItems is 1'));
    }
    if (t.rationaleBullets.length > 5) {
      errors.add(ValidationError(
          path: 'triage.rationale_bullets',
          message: 'maxItems is 5, got ${t.rationaleBullets.length}'));
    }
    for (var i = 0; i < t.rationaleBullets.length; i++) {
      if (t.rationaleBullets[i].isEmpty) {
        errors.add(ValidationError(
            path: 'triage.rationale_bullets[$i]',
            message: 'must be non-empty string'));
      }
    }
  }

  static void _checkVolunteer(
      EvidencePacket p, List<ValidationError> errors) {
    final v = p.volunteer;
    if (v.attestation.isEmpty) {
      errors.add(const ValidationError(
          path: 'volunteer.attestation', message: 'must be non-empty'));
    }
    if (!_localeRe.hasMatch(v.locale)) {
      errors.add(ValidationError(
          path: 'volunteer.locale',
          message:
              '"${v.locale}" must match ^(en|es|tr)(-[A-Z]{2})?\$'));
    }
    if (!_sigHashRe.hasMatch(v.signatureHash)) {
      errors.add(ValidationError(
          path: 'volunteer.signature_hash',
          message:
              '"${v.signatureHash}" must match ^sha256:[0-9a-f]{64}\$'));
    }
  }

  static void _checkAssets(EvidencePacket p, List<ValidationError> errors) {
    for (var i = 0; i < p.images.length; i++) {
      final img = p.images[i];
      final pfx = 'assets.images[$i]';
      if (!_imgRefRe.hasMatch(img.ref)) {
        errors.add(ValidationError(
            path: '$pfx.ref',
            message:
                'must match ^img-[0-9]+\$, got "${img.ref}"'));
      }
      if (!_sha256Re.hasMatch(img.sha256)) {
        errors.add(ValidationError(
            path: '$pfx.sha256',
            message: 'must be 64 lowercase hex chars'));
      }
      if (img.widthPx < 1) {
        errors.add(ValidationError(
            path: '$pfx.width_px',
            message: 'must be >= 1, got ${img.widthPx}'));
      }
      if (img.heightPx < 1) {
        errors.add(ValidationError(
            path: '$pfx.height_px',
            message: 'must be >= 1, got ${img.heightPx}'));
      }
    }

    for (var i = 0; i < p.audio.length; i++) {
      final aud = p.audio[i];
      final pfx = 'assets.audio[$i]';
      if (!_audRefRe.hasMatch(aud.ref)) {
        errors.add(ValidationError(
            path: '$pfx.ref',
            message:
                'must match ^aud-[0-9]+\$, got "${aud.ref}"'));
      }
      if (!_sha256Re.hasMatch(aud.sha256)) {
        errors.add(ValidationError(
            path: '$pfx.sha256',
            message: 'must be 64 lowercase hex chars'));
      }
      if (aud.sampleRateHz != 16000) {
        errors.add(ValidationError(
            path: '$pfx.sample_rate_hz',
            message: 'must be 16000, got ${aud.sampleRateHz}'));
      }
      if (aud.channels != 1) {
        errors.add(ValidationError(
            path: '$pfx.channels',
            message: 'must be 1 (mono), got ${aud.channels}'));
      }
      if (aud.durationS < 0 || aud.durationS > 30) {
        errors.add(ValidationError(
            path: '$pfx.duration_s',
            message: 'must be 0..30, got ${aud.durationS}'));
      }
    }
  }
}
