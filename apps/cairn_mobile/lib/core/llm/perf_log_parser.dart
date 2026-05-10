/// Parser for Cairn benchmark `/perf` log lines.
library;

class ParsedPerfLine {
  const ParsedPerfLine(this.fields);

  final Map<String, String> fields;

  String? get phase => fields['phase'];
  String? get task => fields['task'];

  int? intField(String key) {
    final raw = fields[key];
    if (raw == null) return null;
    final normalized =
        raw.endsWith('ms') ? raw.substring(0, raw.length - 2) : raw;
    return int.tryParse(normalized);
  }

  bool get hasRequiredTimingFields {
    final p = phase;
    if (p == null || intField('wall') == null) return false;
    if (p == 'generate') return intField('ttft') != null;
    return true;
  }
}

ParsedPerfLine? parsePerfLine(String line) {
  final marker = line.indexOf('/perf]');
  if (marker == -1) return null;
  final payload = line.substring(marker + '/perf]'.length).trim();
  if (payload.isEmpty) return null;

  final fields = <String, String>{};
  for (final token in payload.split(RegExp(r'\s+'))) {
    final equals = token.indexOf('=');
    if (equals <= 0 || equals == token.length - 1) continue;
    fields[token.substring(0, equals)] = token.substring(equals + 1);
  }
  if (fields.isEmpty) return null;
  return ParsedPerfLine(fields);
}

List<String> missingRequiredBenchmarkFields(Iterable<String> lines) {
  final missing = <String>{};
  var sawEngineCreate = false;
  var sawGenerate = false;
  var sawImagePreprocess = false;
  var sawParseContract = false;

  for (final line in lines) {
    final parsed = parsePerfLine(line);
    if (parsed == null) continue;
    if (parsed.phase == 'engine_create') sawEngineCreate = true;
    if (parsed.phase == 'generate') sawGenerate = true;
    if (parsed.phase == 'image_preprocess') sawImagePreprocess = true;
    if (parsed.phase == 'parse_contract') sawParseContract = true;
    if (!parsed.hasRequiredTimingFields) {
      missing.add('${parsed.phase ?? 'unknown'}:required_timing');
    }
  }

  if (!sawEngineCreate) missing.add('phase=engine_create');
  if (!sawGenerate) missing.add('phase=generate');
  if (!sawImagePreprocess) missing.add('phase=image_preprocess');
  if (!sawParseContract) missing.add('phase=parse_contract');
  return missing.toList()..sort();
}
