import 'difficulty.dart';

enum GamePalette {
  standard,
  rainbow,
  world11,
  neon,
  pkmn,
  pkmn2,
  glass,
  sky,
  greyscale;

  String get label => switch (this) {
        GamePalette.standard => 'Default',
        GamePalette.rainbow => 'Rainbow',
        GamePalette.world11 => '1-1',
        GamePalette.neon => 'Neon',
        GamePalette.pkmn => 'Kanto',
        GamePalette.pkmn2 => 'Johto',
        GamePalette.glass => 'Glass',
        GamePalette.sky => 'Sky',
        GamePalette.greyscale => 'Greyscale',
      };

  String get storageKey => switch (this) {
        GamePalette.standard => 'default',
        GamePalette.rainbow => 'rainbow',
        GamePalette.world11 => '1-1',
        GamePalette.neon => 'neon',
        GamePalette.pkmn => 'pkmn',
        GamePalette.pkmn2 => 'pkmn2',
        GamePalette.glass => 'glass',
        GamePalette.sky => 'sky',
        GamePalette.greyscale => 'greyscale',
      };

  static GamePalette fromStorageKey(String? key) {
    if (key == 'sea') return GamePalette.glass;
    // Sunglass was folded into Rainbow.
    if (key == 'sunglass') return GamePalette.rainbow;
    // Sunset → Stone → Sky.
    if (key == 'sunset' || key == 'stone') return GamePalette.sky;
    return GamePalette.values.firstWhere(
      (palette) => palette.storageKey == key,
      orElse: () => GamePalette.standard,
    );
  }

  /// Palettes shown in the Settings dropdown (Greyscale hidden for now).
  bool get visibleInMenu => this != GamePalette.greyscale;

  static List<GamePalette> get menuValues =>
      values.where((palette) => palette.visibleInMenu).toList();

  bool get isLockedByDefault => switch (this) {
        GamePalette.world11 ||
        GamePalette.neon ||
        GamePalette.pkmn ||
        GamePalette.pkmn2 ||
        GamePalette.glass ||
        GamePalette.sky =>
          true,
        _ => false,
      };

  String get unlockRequirementText => switch (this) {
        GamePalette.world11 => 'Win 1 game',
        GamePalette.neon => 'Win an Easy game under 8 minutes',
        GamePalette.pkmn => 'Win 4 games in a row',
        GamePalette.pkmn2 => 'Win a Hard game with no mistakes',
        GamePalette.glass => 'Win an Expert game with no mistakes',
        GamePalette.sky => 'Win a Master game',
        _ => '',
      };

  /// Text segments for locked-palette toasts. Highlighted parts are difficulty names.
  List<({String text, bool highlight})> get unlockRequirementParts =>
      switch (this) {
        GamePalette.world11 => const [(text: 'Win 1 game', highlight: false)],
        GamePalette.neon => [
          (text: 'Win an ', highlight: false),
          (text: Difficulty.easy.label, highlight: true),
          (text: ' game under 8 minutes', highlight: false),
        ],
        GamePalette.pkmn => const [
          (text: 'Win 4 games in a row', highlight: false),
        ],
        GamePalette.pkmn2 => [
          (text: 'Win a ', highlight: false),
          (text: Difficulty.hard.label, highlight: true),
          (text: ' game with no mistakes', highlight: false),
        ],
        GamePalette.glass => [
          (text: 'Win an ', highlight: false),
          (text: Difficulty.expert.label, highlight: true),
          (text: ' game with no mistakes', highlight: false),
        ],
        GamePalette.sky => [
          (text: 'Win a ', highlight: false),
          (text: Difficulty.master.label, highlight: true),
          (text: ' game', highlight: false),
        ],
        _ => [(text: unlockRequirementText, highlight: false)],
      };
}
