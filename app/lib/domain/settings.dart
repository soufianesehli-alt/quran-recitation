import 'models/riwaya.dart';

enum ReReciteMode { segment, fullAyah }

/// Which recogniser setup to use. `auto` picks from the device tier.
enum ModelChoice { auto, base, tiny }

/// User settings (docs/SPEC.md §4 settings). Persisted on the device; never audio.
class AppSettings {
  const AppSettings({
    this.riwaya = Riwaya.hafs,
    this.reReciteMode = ReReciteMode.segment,
    this.maxAttempts = 3,
    this.highConfidence = 0.9,
    this.modelChoice = ModelChoice.auto,
    this.liveHighlighting,
    this.firstLaunchDone = false,
    this.devBlockingWordRules = false,
  });

  final Riwaya riwaya;
  final ReReciteMode reReciteMode;
  final int maxAttempts;
  final double highConfidence;
  final ModelChoice modelChoice;

  /// null = decided by the device tier.
  final bool? liveHighlighting;
  final bool firstLaunchDone;

  /// DEV BUILDS ONLY: treat word rules as blocking to try the gating before Phase 5.
  final bool devBlockingWordRules;

  AppSettings copyWith({
    Riwaya? riwaya,
    ReReciteMode? reReciteMode,
    int? maxAttempts,
    ModelChoice? modelChoice,
    bool? Function()? liveHighlighting,
    bool? firstLaunchDone,
    bool? devBlockingWordRules,
  }) => AppSettings(
    riwaya: riwaya ?? this.riwaya,
    reReciteMode: reReciteMode ?? this.reReciteMode,
    maxAttempts: maxAttempts ?? this.maxAttempts,
    highConfidence: highConfidence,
    modelChoice: modelChoice ?? this.modelChoice,
    liveHighlighting: liveHighlighting == null
        ? this.liveHighlighting
        : liveHighlighting(),
    firstLaunchDone: firstLaunchDone ?? this.firstLaunchDone,
    devBlockingWordRules: devBlockingWordRules ?? this.devBlockingWordRules,
  );

  Map<String, String> toMap() => {
    'riwaya': riwaya.id,
    'reReciteMode': reReciteMode.name,
    'maxAttempts': '$maxAttempts',
    'modelChoice': modelChoice.name,
    'liveHighlighting': liveHighlighting?.toString() ?? '',
    'firstLaunchDone': '$firstLaunchDone',
    'devBlockingWordRules': '$devBlockingWordRules',
  };

  static AppSettings fromMap(Map<String, String> m) {
    T pick<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    return AppSettings(
      riwaya: Riwaya.values.firstWhere(
        (r) => r.id == m['riwaya'],
        orElse: () => Riwaya.hafs,
      ),
      reReciteMode: pick(
        ReReciteMode.values,
        m['reReciteMode'],
        ReReciteMode.segment,
      ),
      maxAttempts: (int.tryParse(m['maxAttempts'] ?? '') ?? 3).clamp(1, 10),
      modelChoice: pick(ModelChoice.values, m['modelChoice'], ModelChoice.auto),
      liveHighlighting: switch (m['liveHighlighting']) {
        'true' => true,
        'false' => false,
        _ => null,
      },
      firstLaunchDone: m['firstLaunchDone'] == 'true',
      devBlockingWordRules: m['devBlockingWordRules'] == 'true',
    );
  }
}
