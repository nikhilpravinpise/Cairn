import 'package:cairn_mobile/core/llm/perf_log_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsePerfLine extracts benchmark fields', () {
    final parsed = parsePerfLine(
      '[Cairn/perf] phase=generate task=describe_photo wall=1200ms '
      'ttft=300ms out_chars=80 runtime=native_mtp backend=gpu tok_s=12.5',
    );

    expect(parsed, isNotNull);
    expect(parsed!.phase, 'generate');
    expect(parsed.task, 'describe_photo');
    expect(parsed.intField('wall'), 1200);
    expect(parsed.intField('ttft'), 300);
    expect(parsed.fields['runtime'], 'native_mtp');
    expect(parsed.fields['backend'], 'gpu');
  });

  test('missingRequiredBenchmarkFields returns empty when all phases present',
      () {
    final missing = missingRequiredBenchmarkFields([
      '[Cairn/perf] phase=engine_create wall=10ms',
      '[Cairn/perf] phase=image_preprocess task=describe_photo wall=5ms',
      '[Cairn/perf] phase=generate task=describe_photo wall=20ms ttft=4ms',
      '[Cairn/perf] phase=parse_contract task=describe_photo wall=1ms',
    ]);

    expect(missing, isEmpty);
  });

  test('missingRequiredBenchmarkFields reports missing image_preprocess and parse_contract',
      () {
    final missing = missingRequiredBenchmarkFields([
      '[Cairn/perf] phase=engine_create wall=10ms',
      '[Cairn/perf] phase=generate task=describe_photo wall=20ms ttft=4ms',
    ]);

    expect(missing, contains('phase=image_preprocess'));
    expect(missing, contains('phase=parse_contract'));
    expect(missing, isNot(contains('phase=engine_create')));
    expect(missing, isNot(contains('phase=generate')));
  });

  test('missingRequiredBenchmarkFields reports absent timing', () {
    final missing = missingRequiredBenchmarkFields([
      '[Cairn/perf] phase=generate task=describe_photo wall=20ms',
    ]);

    expect(missing, contains('generate:required_timing'));
    expect(missing, contains('phase=engine_create'));
    expect(missing, contains('phase=image_preprocess'));
    expect(missing, contains('phase=parse_contract'));
  });
}
