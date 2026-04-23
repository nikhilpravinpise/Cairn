/// Extract the first valid top-level JSON object from a model response.
///
/// Mirrors `scripts/eval/eval_baseline.py::_extract_first_json`. Fails loud
/// (returns `null`) — caller decides whether to retry or surface to the user.
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
    if (c == r'\\' && inString) {
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
          return null;
        }
      }
    }
  }
  return null;
}
