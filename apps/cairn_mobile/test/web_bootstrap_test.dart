import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web bootstrap installs flutter_gemma JS dependencies', () {
    final index = File('web/index.html').readAsStringSync();
    final opfsHelper = File('web/opfs_helper.js').readAsStringSync();

    expect(index, contains('@mediapipe/tasks-genai@0.10.27'));
    expect(index, contains('window.FilesetResolver = FilesetResolver'));
    expect(index, contains('window.LlmInference = LlmInference'));
    expect(index, contains('cache_api.js'));
    expect(index, contains('opfs_helper.js'));
    expect(
      index.indexOf('opfs_helper.js'),
      greaterThan(index.indexOf('cache_api.js')),
      reason: 'streaming storage must load after the shared cache helper',
    );
    expect(
      index.indexOf('opfs_helper.js'),
      lessThan(index.indexOf('flutter_bootstrap.js')),
      reason: 'flutter_gemma reads the OPFS global during Flutter startup',
    );
    expect(opfsHelper, contains('window.flutterGemmaOPFS'));
  });
}
