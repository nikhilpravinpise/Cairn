# Cairn system prompt — **v1 LOCKED D4**

> Canonical plain-text form lives at `system_prompt_v1.txt`. That file is the one loaded
> by the Flutter app, the eval harness, and the fine-tune scripts. **Edit that file, not
> this one**, and keep the two in sync.

## Design intent
- Deterministic, schema-locked. Temperature is set at the app layer (`0.2` for
  description, `0.4` for thinking-mode synthesis).
- Concrete structural vocabulary only. No medical / legal / safety-authority language.
- Uncertainty is a first-class output. Low confidence is *preferred* over false
  precision; see rule 4.
- The LLM does **not** compute priority; it describes + classifies. Dart computes score.
- All JSON keys are in English; all free text is in the user's locale (`asked_in`).

## Size
~1.9k tokens under SentencePiece (Gemma tokenizer). Fits inside the 8k context window
with room for 5 images + ~1k of user turns.

## Where it is used
- `apps/cairn_mobile/lib/core/llm/session.dart` via `createChat(systemInstruction: …)`.
- `scripts/eval/eval_baseline.py` as the `system` block for all 3 prompt strategies
  (`strict_schema`, `cot_then_schema`, `schema_only`).
- `finetune/` — prepended as `system` turn in every ShareGPT training example.
