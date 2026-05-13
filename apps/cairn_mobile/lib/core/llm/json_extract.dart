/// Extract the first valid top-level JSON object from a model response.
///
/// Mirrors `scripts/eval/eval_baseline.py::_extract_first_json`. Fails loud
/// (returns `null`) — caller decides whether to retry or surface to the user.
///
/// Includes a small Gemma-specific repair pass that strips stray empty-string
/// tokens (`""`) which appear at structural positions in the output. This is
/// a documented Gemma 4 streaming quirk where a sentinel token leaks into
/// tool-call JSON (see vllm-project/vllm#38946 and #38910). Without the
/// repair, otherwise-recoverable describe_photo turns crash with
/// `GemmaContractError(describe_photo): required tool call "describe_photo"
/// missing` even though every required field was emitted by the model.
library;

import 'dart:convert';

Map<String, Object?>? extractFirstJsonObject(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) return null;
  // Walk forward, tracking brace depth and string state, to find the matching
  // `}`. This handles braces inside strings.
  var depth = 0;
  var inString = false;
  var escape = false;
  for (var i = start; i < raw.length; i++) {
    final c = raw[i];
    if (escape) {
      escape = false;
      continue;
    }
    // Single backslash character. Cannot use `r'\'` — raw strings cannot end
    // with a backslash — so we use the escape sequence `'\\'` which is one char.
    if (c == '\\' && inString) {
      escape = true;
      continue;
    }
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (c == '{') depth += 1;
    if (c == '}') {
      depth -= 1;
      if (depth == 0) {
        final candidate = raw.substring(start, i + 1);
        try {
          return jsonDecode(candidate) as Map<String, Object?>;
        } on FormatException {
          // Gemma 4 occasionally emits a stray `""` token between fields.
          // Strip orphan empty strings at structural positions and retry.
          final repaired = repairOrphanEmptyStrings(candidate);
          if (repaired != candidate) {
            try {
              return jsonDecode(repaired) as Map<String, Object?>;
            } on FormatException {
              return null;
            }
          }
          return null;
        }
      }
    }
  }
  return null;
}

/// Remove orphan `""` tokens that sit at structural positions inside a JSON
/// blob — i.e. an empty string that is neither a key nor a value, but a stray
/// token between commas / inside an object body.
///
/// Patterns repaired:
///   `, "" ,`   → `,`     (orphan in middle of object/array)
///   `{ "" ,`   → `{`     (orphan at start of object)
///   `, "" }`   → `}`     (orphan at end of object)
///   `[ "" ,`   → `[`     (orphan at start of array)
///   `, "" ]`   → `]`     (orphan at end of array)
///
/// String-aware: never touches `""` that lives inside a quoted string value.
/// If no orphan is found the input is returned unchanged.
String repairOrphanEmptyStrings(String s) {
  final result = StringBuffer();
  var i = 0;
  var inString = false;
  var escape = false;
  bool isWs(String ch) => ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

  while (i < s.length) {
    final c = s[i];
    if (inString) {
      result.write(c);
      if (escape) {
        escape = false;
      } else if (c == '\\') {
        escape = true;
      } else if (c == '"') {
        inString = false;
      }
      i++;
      continue;
    }
    if (c == '"') {
      // Possible empty string `""`. Check the next char.
      if (i + 1 < s.length && s[i + 1] == '"') {
        // Find next non-WS char after the `""`.
        var j = i + 2;
        while (j < s.length && isWs(s[j])) {
          j++;
        }
        // Find prev non-WS char already emitted to result.
        final written = result.toString();
        var k = written.length - 1;
        while (k >= 0 && isWs(written[k])) {
          k--;
        }
        final prev = k >= 0 ? written[k] : '';
        final next = j < s.length ? s[j] : '';

        // It's an orphan iff both sides are structural (no `:` meaning it's
        // not a key, no other value-position context).
        final structuralPrev = prev == ',' || prev == '{' || prev == '[';
        final structuralNext = next == ',' || next == '}' || next == ']';

        if (structuralPrev && structuralNext) {
          // Skip the `""` token entirely.
          if (prev == ',' && (next == '}' || next == ']')) {
            // Drop the trailing comma we already emitted.
            final trimmed = written.substring(0, k);
            result
              ..clear()
              ..write(trimmed);
            i = j;
          } else if ((prev == '{' || prev == '[') && next == ',') {
            // Skip the orphan and the following comma so we don't end up with
            // `{,` or `[,`.
            i = j + 1;
          } else {
            // Middle position: `, "" ,` — keep one comma, drop the other.
            i = j + 1;
          }
          continue;
        }
      }
      // Normal start of string.
      result.write(c);
      inString = true;
      i++;
      continue;
    }
    result.write(c);
    i++;
  }
  return result.toString();
}
