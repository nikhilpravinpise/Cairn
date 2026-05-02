import 'package:cairn_mobile/core/llm/model_registry.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide ModelSpec;
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const String _kHfBase = 'https://huggingface.co/';
const String _kHfResolvePath = '/resolve/main/';

String _expectedUrl(String repo, String filename) =>
    '$_kHfBase$repo$_kHfResolvePath$filename';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Registry completeness
  // -------------------------------------------------------------------------

  test('registry contains both e2b and e4b', () {
    expect(models.containsKey('e2b'), isTrue,
        reason: 'e2b is the S23-FE Android target per §1.2');
    expect(models.containsKey('e4b'), isTrue,
        reason: 'e4b retained for future use (out of scope for S23-FE per §1.2)');
  });

  // -------------------------------------------------------------------------
  // E2B — primary S23-FE Android target (§1.2)
  // -------------------------------------------------------------------------

  group('e2b metadata', () {
    final spec = models['e2b']!;

    test('key', () => expect(spec.key, 'e2b'));
    test('hfRepo', () {
      expect(spec.hfRepo, 'litert-community/gemma-4-E2B-it-litert-lm');
    });
    test('quant', () => expect(spec.quant, 'int4'));
    test('contextTokens', () => expect(spec.contextTokens, 8192));
    test('modalities contains text and image', () {
      expect(spec.modalities, containsAll(['text', 'image']));
    });
    test('web filename', () {
      expect(spec.taskFilenameWeb, 'gemma-4-E2B-it-web.task');
    });
    test('android filename', () {
      expect(spec.taskFilenameAndroid, 'gemma-4-E2B-it.litertlm');
    });
  });

  group('e2b filename routing', () {
    final spec = models['e2b']!;

    test('getTaskFilename(true) returns web filename', () {
      expect(spec.getTaskFilename(true), spec.taskFilenameWeb);
    });
    test('getTaskFilename(false) returns android filename', () {
      expect(spec.getTaskFilename(false), spec.taskFilenameAndroid);
    });
  });

  group('e2b download URLs', () {
    final spec = models['e2b']!;

    test('hfDownloadUrl(isWeb=true) is well-formed HuggingFace URL with web filename', () {
      final url = spec.hfDownloadUrl(true);
      expect(url, _expectedUrl(spec.hfRepo, spec.taskFilenameWeb));
      expect(url, startsWith(_kHfBase));
      expect(url, contains(_kHfResolvePath));
      expect(url, endsWith('.task'));
    });

    test('hfDownloadUrl(isWeb=false) is well-formed HuggingFace URL with android filename', () {
      final url = spec.hfDownloadUrl(false);
      expect(url, _expectedUrl(spec.hfRepo, spec.taskFilenameAndroid));
      expect(url, startsWith(_kHfBase));
      expect(url, contains(_kHfResolvePath));
      expect(url, endsWith('.litertlm'));
    });

    test('resolvedDownloadUrl in test environment (kIsWeb=false) returns android URL', () {
      // flutter test runs outside a browser, so kIsWeb == false.
      expect(spec.resolvedDownloadUrl, spec.hfDownloadUrl(false));
      expect(spec.resolvedDownloadUrl, endsWith('.litertlm'));
    });
  });

  group('e2b file types', () {
    final spec = models['e2b']!;

    test('fileType(isWeb=true) returns ModelFileType.task', () {
      expect(spec.fileType(isWeb: true), ModelFileType.task);
    });

    test('fileType(isWeb=false) returns ModelFileType.litertlm', () {
      expect(spec.fileType(isWeb: false), ModelFileType.litertlm);
    });

    test('resolvedFileType in test environment (kIsWeb=false) returns litertlm', () {
      // flutter test runs outside a browser, so kIsWeb == false.
      expect(spec.resolvedFileType, ModelFileType.litertlm);
    });
  });

  group('e2b Exynos compatibility (§1.2)', () {
    final spec = models['e2b']!;

    test('android artifact is not Qualcomm-specific (Exynos 2200 target)', () {
      final fn = spec.taskFilenameAndroid.toLowerCase();
      expect(fn, isNot(contains('qualcomm')),
          reason: 'S23-FE uses Exynos 2200, not Qualcomm');
      expect(fn, isNot(contains('qdsp')),
          reason: 'QDSP is a Qualcomm DSP — not available on Exynos');
      expect(fn, isNot(contains('aiehub')),
          reason: 'AI Engine Hub is Qualcomm-specific');
    });

    test('hfRepo is generic litert-community, not Qualcomm AI Hub', () {
      final repo = spec.hfRepo.toLowerCase();
      expect(repo, startsWith('litert-community/'),
          reason: 'must use the generic LiteRT-LM community repo');
      expect(repo, isNot(contains('qualcomm')));
      expect(repo, isNot(contains('aihub')));
    });
  });

  // -------------------------------------------------------------------------
  // E4B — retained in registry; out of scope for S23 FE per §1.2
  // -------------------------------------------------------------------------

  group('e4b metadata', () {
    final spec = models['e4b']!;

    test('key', () => expect(spec.key, 'e4b'));
    test('hfRepo', () {
      expect(spec.hfRepo, 'litert-community/gemma-4-E4B-it-litert-lm');
    });
    test('web filename ends with .task', () {
      expect(spec.taskFilenameWeb, endsWith('.task'));
    });
    test('android filename ends with .litertlm', () {
      expect(spec.taskFilenameAndroid, endsWith('.litertlm'));
    });
  });

  group('e4b file types', () {
    final spec = models['e4b']!;

    test('fileType(isWeb=true) returns ModelFileType.task', () {
      expect(spec.fileType(isWeb: true), ModelFileType.task);
    });
    test('fileType(isWeb=false) returns ModelFileType.litertlm', () {
      expect(spec.fileType(isWeb: false), ModelFileType.litertlm);
    });
  });

  // -------------------------------------------------------------------------
  // URL structure invariants across all models
  // -------------------------------------------------------------------------

  group('URL structure invariants', () {
    for (final entry in models.entries) {
      final key = entry.key;
      final spec = entry.value;

      test('$key web URL ends with .task', () {
        expect(spec.hfDownloadUrl(true), endsWith('.task'));
      });

      test('$key android URL ends with .litertlm', () {
        expect(spec.hfDownloadUrl(false), endsWith('.litertlm'));
      });

      test('$key web URL contains HuggingFace resolve path', () {
        expect(spec.hfDownloadUrl(true), contains(_kHfResolvePath));
      });

      test('$key android URL contains HuggingFace resolve path', () {
        expect(spec.hfDownloadUrl(false), contains(_kHfResolvePath));
      });

      test('$key web and android URLs are distinct', () {
        expect(
          spec.hfDownloadUrl(true),
          isNot(spec.hfDownloadUrl(false)),
          reason: 'web and android artifacts must differ',
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // File-type / filename extension coherence
  // -------------------------------------------------------------------------

  group('file-type / filename coherence', () {
    for (final entry in models.entries) {
      final key = entry.key;
      final spec = entry.value;

      test('$key web: fileType=task matches .task filename', () {
        expect(spec.fileType(isWeb: true), ModelFileType.task);
        expect(spec.taskFilenameWeb, endsWith('.task'));
      });

      test('$key android: fileType=litertlm matches .litertlm filename', () {
        expect(spec.fileType(isWeb: false), ModelFileType.litertlm);
        expect(spec.taskFilenameAndroid, endsWith('.litertlm'));
      });
    }
  });
}
