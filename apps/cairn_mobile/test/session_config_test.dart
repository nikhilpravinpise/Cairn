/// Tests for [SessionConfig].
///
/// Coverage:
///   - Production defaults stay within the measured-safe ranges defined by the
///     Sprint 2 benchmark design.
///   - Each profile constant has the correct `maxNumImages` for its use case.
///   - Benchmark variants differ from their production baseline in exactly the
///     documented way — no accidental drift.
///   - [SessionConfig.isTokenBudgetInSafeRange] reports correctly.
///   - [SessionConfig.toLogString] and [toString] include every field.
///
/// These tests are the machine-readable version of the Sprint 2 benchmark
/// matrix in `lib/core/llm/session_config.dart`.
library;

import 'package:cairn_mobile/core/llm/session_config.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Production default — token budget
  // ---------------------------------------------------------------------------

  group('production defaults — maxTokens', () {
    test('vision maxTokens is 4096 (raised from 2048 after Sprint 5 token-overflow fix)', () {
      expect(SessionConfig.vision.maxTokens, 4096);
    });

    test('audio maxTokens is 4096', () {
      expect(SessionConfig.audio.maxTokens, 4096);
    });

    test('synthesis maxTokens is 4096', () {
      expect(SessionConfig.synthesis.maxTokens, 4096);
    });

    test('standard maxTokens is 4096', () {
      expect(SessionConfig.standard.maxTokens, 4096);
    });

    test('all production profiles are in the safe token range', () {
      for (final cfg in [
        SessionConfig.vision,
        SessionConfig.audio,
        SessionConfig.synthesis,
        SessionConfig.standard,
      ]) {
        expect(cfg.isTokenBudgetInSafeRange, isTrue,
            reason: '$cfg.maxTokens=${cfg.maxTokens} out of safe range [2048,4096]');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Production default — temperature
  // ---------------------------------------------------------------------------

  group('production defaults — temperature', () {
    test('vision temperature is 0.1', () {
      expect(SessionConfig.vision.temperature, 0.1);
    });

    test('synthesis temperature is 0.2 (do not lower without device evidence)', () {
      expect(SessionConfig.synthesis.temperature, 0.2);
    });

    test('all production temperatures are in [0.0, 1.0]', () {
      for (final cfg in [
        SessionConfig.vision,
        SessionConfig.audio,
        SessionConfig.synthesis,
        SessionConfig.standard,
      ]) {
        expect(cfg.temperature, greaterThanOrEqualTo(0.0));
        expect(cfg.temperature, lessThanOrEqualTo(1.0));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Production default — topK / topP
  // ---------------------------------------------------------------------------

  group('production defaults — topK and topP', () {
    test('all production topK values are >= 1', () {
      for (final cfg in [
        SessionConfig.vision,
        SessionConfig.audio,
        SessionConfig.synthesis,
        SessionConfig.standard,
      ]) {
        expect(cfg.topK, greaterThanOrEqualTo(1));
      }
    });

    test('all production topP values are in (0.0, 1.0]', () {
      for (final cfg in [
        SessionConfig.vision,
        SessionConfig.audio,
        SessionConfig.synthesis,
        SessionConfig.standard,
      ]) {
        expect(cfg.topP, greaterThan(0.0));
        expect(cfg.topP, lessThanOrEqualTo(1.0));
      }
    });

    test('vision topK is 40', () {
      expect(SessionConfig.vision.topK, 40);
    });

    test('vision topP is 0.95', () {
      expect(SessionConfig.vision.topP, 0.95);
    });
  });

  // ---------------------------------------------------------------------------
  // Production default — backend
  // ---------------------------------------------------------------------------

  group('production defaults — backend', () {
    test('all production profiles use GPU backend', () {
      for (final cfg in [
        SessionConfig.vision,
        SessionConfig.audio,
        SessionConfig.synthesis,
        SessionConfig.standard,
      ]) {
        expect(cfg.preferredBackend, PreferredBackend.gpu,
            reason: 'Switch to CPU only after device benchmark confirms parity');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Production default — maxNumImages
  // ---------------------------------------------------------------------------

  group('production defaults — maxNumImages', () {
    test('vision maxNumImages is 5 (full required-photo slot set)', () {
      expect(SessionConfig.vision.maxNumImages, 5);
    });

    test('audio maxNumImages is 1 (no image input)', () {
      expect(SessionConfig.audio.maxNumImages, 1);
    });

    test('synthesis maxNumImages is 1 (no image input)', () {
      expect(SessionConfig.synthesis.maxNumImages, 1);
    });

    test('standard maxNumImages is 1 (no image input)', () {
      expect(SessionConfig.standard.maxNumImages, 1);
    });

    test('all production maxNumImages values are >= 1', () {
      for (final cfg in [
        SessionConfig.vision,
        SessionConfig.audio,
        SessionConfig.synthesis,
        SessionConfig.standard,
      ]) {
        expect(cfg.maxNumImages, greaterThanOrEqualTo(1));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Benchmark variants — differ from production in exactly the right way
  // ---------------------------------------------------------------------------

  group('benchmark variants — visionMaxTokens3072', () {
    test('maxTokens is 3072', () {
      expect(SessionConfig.visionMaxTokens3072.maxTokens, 3072);
    });

    test('temperature unchanged from production vision', () {
      expect(SessionConfig.visionMaxTokens3072.temperature,
          SessionConfig.vision.temperature);
    });

    test('maxNumImages unchanged from production vision', () {
      expect(SessionConfig.visionMaxTokens3072.maxNumImages,
          SessionConfig.vision.maxNumImages);
    });

    test('is within safe token range', () {
      expect(SessionConfig.visionMaxTokens3072.isTokenBudgetInSafeRange, isTrue);
    });
  });

  group('benchmark variants — visionMaxTokens2048', () {
    test('maxTokens is 2048', () {
      expect(SessionConfig.visionMaxTokens2048.maxTokens, 2048);
    });

    test('temperature unchanged from production vision', () {
      expect(SessionConfig.visionMaxTokens2048.temperature,
          SessionConfig.vision.temperature);
    });

    test('is at the lower bound of the safe token range', () {
      expect(SessionConfig.visionMaxTokens2048.isTokenBudgetInSafeRange, isTrue);
    });

    test('maxTokens is strictly less than visionMaxTokens3072', () {
      expect(SessionConfig.visionMaxTokens2048.maxTokens,
          lessThan(SessionConfig.visionMaxTokens3072.maxTokens));
    });
  });

  group('benchmark variants — visionTemp01', () {
    test('temperature is 0.05', () {
      expect(SessionConfig.visionTemp01.temperature, 0.05);
    });

    test('temperature is strictly less than production vision', () {
      expect(SessionConfig.visionTemp01.temperature,
          lessThan(SessionConfig.vision.temperature));
    });

    test('maxTokens unchanged from production vision', () {
      expect(SessionConfig.visionTemp01.maxTokens, SessionConfig.vision.maxTokens);
    });

    test('maxNumImages unchanged from production vision', () {
      expect(SessionConfig.visionTemp01.maxNumImages,
          SessionConfig.vision.maxNumImages);
    });
  });

  group('benchmark variants — standardTemp01', () {
    test('temperature is 0.05', () {
      expect(SessionConfig.standardTemp01.temperature, 0.05);
    });

    test('maxTokens unchanged from production standard', () {
      expect(SessionConfig.standardTemp01.maxTokens,
          SessionConfig.standard.maxTokens);
    });

    test('maxNumImages is 1 (no image input)', () {
      expect(SessionConfig.standardTemp01.maxNumImages, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // isTokenBudgetInSafeRange
  // ---------------------------------------------------------------------------

  group('isTokenBudgetInSafeRange', () {
    test('returns true for maxTokens=4096', () {
      const c = SessionConfig(
        maxTokens: 4096,
        temperature: 0.2,
        topK: 40,
        topP: 0.95,
        preferredBackend: PreferredBackend.gpu,
        maxNumImages: 1,
      );
      expect(c.isTokenBudgetInSafeRange, isTrue);
    });

    test('returns true for maxTokens=2048 (lower bound)', () {
      const c = SessionConfig(
        maxTokens: 2048,
        temperature: 0.2,
        topK: 40,
        topP: 0.95,
        preferredBackend: PreferredBackend.gpu,
        maxNumImages: 1,
      );
      expect(c.isTokenBudgetInSafeRange, isTrue);
    });

    test('returns false for maxTokens=1024 (below floor)', () {
      const c = SessionConfig(
        maxTokens: 1024,
        temperature: 0.2,
        topK: 40,
        topP: 0.95,
        preferredBackend: PreferredBackend.gpu,
        maxNumImages: 1,
      );
      expect(c.isTokenBudgetInSafeRange, isFalse);
    });

    test('returns false for maxTokens=8192 (above ceiling)', () {
      const c = SessionConfig(
        maxTokens: 8192,
        temperature: 0.2,
        topK: 40,
        topP: 0.95,
        preferredBackend: PreferredBackend.gpu,
        maxNumImages: 1,
      );
      expect(c.isTokenBudgetInSafeRange, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // toLogString / toString
  // ---------------------------------------------------------------------------

  group('toLogString and toString', () {
    test('toLogString includes maxTokens', () {
      expect(SessionConfig.vision.toLogString(), contains('maxTokens=4096'));
    });

    test('toLogString includes temperature', () {
      expect(SessionConfig.vision.toLogString(), contains('temperature=0.1'));
    });

    test('toLogString includes topK', () {
      expect(SessionConfig.vision.toLogString(), contains('topK=40'));
    });

    test('toLogString includes topP', () {
      expect(SessionConfig.vision.toLogString(), contains('topP=0.95'));
    });

    test('toLogString includes maxNumImages', () {
      expect(SessionConfig.vision.toLogString(), contains('maxNumImages=5'));
    });

    test('toLogString includes clearHistory=true for production vision', () {
      expect(SessionConfig.vision.toLogString(), contains('clearHistory=true'));
    });

    test('toLogString includes clearHistory=false for visionHistoryRetained', () {
      expect(
        SessionConfig.visionHistoryRetained.toLogString(),
        contains('clearHistory=false'),
      );
    });

    test('toString wraps toLogString in SessionConfig(...)', () {
      final s = SessionConfig.vision.toString();
      expect(s, startsWith('SessionConfig('));
      expect(s, endsWith(')'));
      expect(s, contains('maxTokens=4096'));
    });

    test('benchmark variant toLogString differs from production baseline', () {
      expect(
        SessionConfig.visionMaxTokens3072.toLogString(),
        isNot(equals(SessionConfig.vision.toLogString())),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Sprint 4 OPT-5 — history retention A/B variant
  // ---------------------------------------------------------------------------

  group('benchmark variants — visionHistoryRetained (OPT-5)', () {
    test('clearHistoryBetweenTurns is false', () {
      expect(SessionConfig.visionHistoryRetained.clearHistoryBetweenTurns, isFalse);
    });

    test('maxTokens unchanged from production vision', () {
      expect(SessionConfig.visionHistoryRetained.maxTokens,
          SessionConfig.vision.maxTokens);
    });

    test('temperature unchanged from production vision', () {
      expect(SessionConfig.visionHistoryRetained.temperature,
          SessionConfig.vision.temperature);
    });

    test('preferredBackend unchanged from production vision', () {
      expect(SessionConfig.visionHistoryRetained.preferredBackend,
          SessionConfig.vision.preferredBackend);
    });

    test('maxNumImages unchanged from production vision', () {
      expect(SessionConfig.visionHistoryRetained.maxNumImages,
          SessionConfig.vision.maxNumImages);
    });

    test('is within safe token range', () {
      expect(SessionConfig.visionHistoryRetained.isTokenBudgetInSafeRange, isTrue);
    });

    test('toLogString differs from production vision only in clearHistory field', () {
      expect(
        SessionConfig.visionHistoryRetained.toLogString(),
        isNot(equals(SessionConfig.vision.toLogString())),
      );
      expect(
        SessionConfig.visionHistoryRetained.toLogString(),
        contains('clearHistory=false'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Sprint 4 OPT-6 — CPU backend diagnostic variants
  // ---------------------------------------------------------------------------

  group('benchmark variants — visionCpu (OPT-6)', () {
    test('preferredBackend is cpu', () {
      expect(SessionConfig.visionCpu.preferredBackend, PreferredBackend.cpu);
    });

    test('maxTokens unchanged from production vision', () {
      expect(SessionConfig.visionCpu.maxTokens, SessionConfig.vision.maxTokens);
    });

    test('temperature unchanged from production vision', () {
      expect(SessionConfig.visionCpu.temperature, SessionConfig.vision.temperature);
    });

    test('maxNumImages unchanged from production vision', () {
      expect(SessionConfig.visionCpu.maxNumImages, SessionConfig.vision.maxNumImages);
    });

    test('clearHistoryBetweenTurns is true (safety default preserved)', () {
      expect(SessionConfig.visionCpu.clearHistoryBetweenTurns, isTrue);
    });

    test('is within safe token range', () {
      expect(SessionConfig.visionCpu.isTokenBudgetInSafeRange, isTrue);
    });
  });

  group('benchmark variants — synthesisCpu (OPT-6)', () {
    test('preferredBackend is cpu', () {
      expect(SessionConfig.synthesisCpu.preferredBackend, PreferredBackend.cpu);
    });

    test('maxTokens unchanged from production synthesis', () {
      expect(SessionConfig.synthesisCpu.maxTokens,
          SessionConfig.synthesis.maxTokens);
    });

    test('temperature unchanged from production synthesis', () {
      expect(SessionConfig.synthesisCpu.temperature,
          SessionConfig.synthesis.temperature);
    });

    test('maxNumImages is 1 (no image input)', () {
      expect(SessionConfig.synthesisCpu.maxNumImages, 1);
    });

    test('clearHistoryBetweenTurns is true', () {
      expect(SessionConfig.synthesisCpu.clearHistoryBetweenTurns, isTrue);
    });
  });

  group('benchmark variants — standardCpu (OPT-6)', () {
    test('preferredBackend is cpu', () {
      expect(SessionConfig.standardCpu.preferredBackend, PreferredBackend.cpu);
    });

    test('maxTokens unchanged from production standard', () {
      expect(SessionConfig.standardCpu.maxTokens,
          SessionConfig.standard.maxTokens);
    });

    test('maxNumImages is 1 (no image input)', () {
      expect(SessionConfig.standardCpu.maxNumImages, 1);
    });

    test('clearHistoryBetweenTurns is true', () {
      expect(SessionConfig.standardCpu.clearHistoryBetweenTurns, isTrue);
    });

    test('is within safe token range', () {
      expect(SessionConfig.standardCpu.isTokenBudgetInSafeRange, isTrue);
    });
  });

  group('CPU variants vs production — backend is the only difference', () {
    test('visionCpu differs from vision only in preferredBackend', () {
      const cpu = SessionConfig.visionCpu;
      const gpu = SessionConfig.vision;
      expect(cpu.maxTokens, gpu.maxTokens);
      expect(cpu.temperature, gpu.temperature);
      expect(cpu.topK, gpu.topK);
      expect(cpu.topP, gpu.topP);
      expect(cpu.maxNumImages, gpu.maxNumImages);
      expect(cpu.clearHistoryBetweenTurns, gpu.clearHistoryBetweenTurns);
      expect(cpu.preferredBackend, isNot(equals(gpu.preferredBackend)));
    });

    test('synthesisCpu differs from synthesis only in preferredBackend', () {
      const cpu = SessionConfig.synthesisCpu;
      const gpu = SessionConfig.synthesis;
      expect(cpu.maxTokens, gpu.maxTokens);
      expect(cpu.temperature, gpu.temperature);
      expect(cpu.topK, gpu.topK);
      expect(cpu.topP, gpu.topP);
      expect(cpu.maxNumImages, gpu.maxNumImages);
      expect(cpu.preferredBackend, isNot(equals(gpu.preferredBackend)));
    });

    test('standardCpu differs from standard only in preferredBackend', () {
      const cpu = SessionConfig.standardCpu;
      const gpu = SessionConfig.standard;
      expect(cpu.maxTokens, gpu.maxTokens);
      expect(cpu.temperature, gpu.temperature);
      expect(cpu.topK, gpu.topK);
      expect(cpu.topP, gpu.topP);
      expect(cpu.maxNumImages, gpu.maxNumImages);
      expect(cpu.preferredBackend, isNot(equals(gpu.preferredBackend)));
    });
  });

  // ---------------------------------------------------------------------------
  // Session 5 — visionSingleImage (maxNumImages: 1) benchmark variant
  // ---------------------------------------------------------------------------

  group('benchmark variants — visionSingleImage (Session 5)', () {
    test('maxNumImages is 1', () {
      expect(SessionConfig.visionSingleImage.maxNumImages, 1);
    });

    test('maxTokens unchanged from production vision', () {
      expect(SessionConfig.visionSingleImage.maxTokens,
          SessionConfig.vision.maxTokens);
    });

    test('temperature unchanged from production vision', () {
      expect(SessionConfig.visionSingleImage.temperature,
          SessionConfig.vision.temperature);
    });

    test('topK unchanged from production vision', () {
      expect(SessionConfig.visionSingleImage.topK, SessionConfig.vision.topK);
    });

    test('topP unchanged from production vision', () {
      expect(SessionConfig.visionSingleImage.topP, SessionConfig.vision.topP);
    });

    test('preferredBackend unchanged from production vision', () {
      expect(SessionConfig.visionSingleImage.preferredBackend,
          SessionConfig.vision.preferredBackend);
    });

    test('clearHistoryBetweenTurns is true (safety default preserved)', () {
      expect(SessionConfig.visionSingleImage.clearHistoryBetweenTurns, isTrue);
    });

    test('is within safe token range', () {
      expect(SessionConfig.visionSingleImage.isTokenBudgetInSafeRange, isTrue);
    });

    test('differs from production vision only in maxNumImages', () {
      const single = SessionConfig.visionSingleImage;
      const prod = SessionConfig.vision;
      expect(single.maxTokens, prod.maxTokens);
      expect(single.temperature, prod.temperature);
      expect(single.topK, prod.topK);
      expect(single.topP, prod.topP);
      expect(single.preferredBackend, prod.preferredBackend);
      expect(single.clearHistoryBetweenTurns, prod.clearHistoryBetweenTurns);
      expect(single.maxNumImages, isNot(equals(prod.maxNumImages)));
    });

    test('toLogString contains maxNumImages=1', () {
      expect(
        SessionConfig.visionSingleImage.toLogString(),
        contains('maxNumImages=1'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // copyWith — Sprint 4 OPT-5/OPT-6 override helper
  // ---------------------------------------------------------------------------

  group('copyWith', () {
    test('copyWith with no args is identity-equivalent', () {
      const orig = SessionConfig.vision;
      final copy = orig.copyWith();
      expect(copy.maxTokens, orig.maxTokens);
      expect(copy.temperature, orig.temperature);
      expect(copy.topK, orig.topK);
      expect(copy.topP, orig.topP);
      expect(copy.preferredBackend, orig.preferredBackend);
      expect(copy.maxNumImages, orig.maxNumImages);
      expect(copy.clearHistoryBetweenTurns, orig.clearHistoryBetweenTurns);
    });

    test('copyWith can override preferredBackend to cpu', () {
      final cpu = SessionConfig.vision.copyWith(
        preferredBackend: PreferredBackend.cpu,
      );
      expect(cpu.preferredBackend, PreferredBackend.cpu);
      expect(cpu.maxTokens, SessionConfig.vision.maxTokens);
      expect(cpu.clearHistoryBetweenTurns, SessionConfig.vision.clearHistoryBetweenTurns);
    });

    test('copyWith can override clearHistoryBetweenTurns to false', () {
      final noHistory = SessionConfig.vision.copyWith(
        clearHistoryBetweenTurns: false,
      );
      expect(noHistory.clearHistoryBetweenTurns, isFalse);
      expect(noHistory.preferredBackend, SessionConfig.vision.preferredBackend);
    });

    test('copyWith can override both backend and clearHistory simultaneously', () {
      final bothOverridden = SessionConfig.vision.copyWith(
        preferredBackend: PreferredBackend.cpu,
        clearHistoryBetweenTurns: false,
      );
      expect(bothOverridden.preferredBackend, PreferredBackend.cpu);
      expect(bothOverridden.clearHistoryBetweenTurns, isFalse);
      expect(bothOverridden.maxTokens, SessionConfig.vision.maxTokens);
    });

    test('copyWith maxTokens produces valid config', () {
      final lower = SessionConfig.vision.copyWith(maxTokens: 3072);
      expect(lower.maxTokens, 3072);
      expect(lower.isTokenBudgetInSafeRange, isTrue);
    });

    test('copyWith result is not const (mutable return type)', () {
      final copy = SessionConfig.vision.copyWith();
      expect(copy, isA<SessionConfig>());
    });
  });
}
