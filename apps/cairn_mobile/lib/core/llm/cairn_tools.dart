/// Gemma 4 tool/function schemas for Cairn's structured LLM contracts.
library;

import 'package:flutter_gemma/flutter_gemma.dart';

const _tagEnum = [
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

const describePhotoTool = Tool(
  name: 'describe_photo',
  description:
      'Return one FEMA P-154 observation for the supplied building photo.',
  parameters: {
    'type': 'object',
    'properties': {
      'observation_id': {'type': 'string'},
      'prompt_id': {'type': 'string'},
      'asked_in': {'type': 'string'},
      'image_refs': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'model_description': {
        'type': 'string',
        'description': 'At most 3 sentences and 60 words.',
      },
      'model_tags': {
        'type': 'array',
        'items': {'type': 'string', 'enum': _tagEnum},
        'minItems': 1,
        'maxItems': 5,
      },
      'model_confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
      'bbox_annotations': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'box_2d': {
              'type': 'array',
              'items': {'type': 'integer', 'minimum': 0, 'maximum': 1000},
              'minItems': 4,
              'maxItems': 4,
            },
            'label': {'type': 'string'},
            'image_ref': {'type': 'string'},
          },
          'required': ['box_2d', 'label'],
        },
        'maxItems': 1,
      },
    },
    'required': [
      'observation_id',
      'prompt_id',
      'asked_in',
      'image_refs',
      'model_description',
      'model_tags',
      'model_confidence',
      'bbox_annotations',
    ],
  },
);

const askFollowupTool = Tool(
  name: 'ask_followup',
  description:
      'Return a single volunteer follow-up question, or null if none is needed.',
  parameters: {
    'type': 'object',
    'properties': {
      'asked_in': {'type': 'string'},
      'followup': {
        'anyOf': [
          {'type': 'null'},
          {
            'type': 'object',
            'properties': {
              'target_observation_id': {'type': 'string'},
              'question': {'type': 'string'},
            },
            'required': ['target_observation_id', 'question'],
          },
        ],
      },
    },
    'required': ['asked_in', 'followup'],
  },
);

const protocolAnswerTool = Tool(
  name: 'protocol_answer',
  description:
      'Map one volunteer free-text answer onto exactly one FEMA protocol field.',
  parameters: {
    'type': 'object',
    'properties': {
      'asked_in': {'type': 'string'},
      'question_id': {'type': 'string'},
      'protocol_answers_delta': {
        'type': 'object',
        'minProperties': 1,
        'maxProperties': 1,
      },
    },
    'required': ['asked_in', 'question_id', 'protocol_answers_delta'],
  },
);

const synthesizeTool = Tool(
  name: 'synthesize',
  description:
      'Return a triage rationale draft. Do not include priority score or band.',
  parameters: {
    'type': 'object',
    'properties': {
      'triage_draft': {
        'type': 'object',
        'properties': {
          'rationale_bullets': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'uncertainty_notes': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'recommend_engineer_followup': {'type': 'boolean'},
        },
        'required': [
          'rationale_bullets',
          'uncertainty_notes',
          'recommend_engineer_followup',
        ],
      },
    },
    'required': ['triage_draft'],
  },
);

List<Tool> toolsForSession({
  required bool supportImage,
  required bool supportAudio,
  required bool isThinking,
}) {
  if (supportImage) return const [describePhotoTool];
  if (supportAudio) return const [];
  if (isThinking) return const [synthesizeTool];
  return const [askFollowupTool, protocolAnswerTool];
}
