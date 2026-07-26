import 'difficulty.dart';

enum GamePalette {
  standard,
  rainbow,
  world11,
  neon,
  pkmn,
  pkmn2,
  glass,
  sunset,
  greyscale;

  String get label => switch (this) {
        GamePalette.standard => 'Default',
        GamePalette.rainbow => 'Rainbow',
        GamePalette.world11 => '1-1',
        GamePalette.neon => 'Neon',
        GamePalette.pkmn => 'Kanto',
        GamePalette.pkmn2 => 'Johto',
        GamePalette.glass => 'Glass',
        GamePalette.sunset => 'Sunset',
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
        GamePalette.sunset => 'sunset',
        GamePalette.greyscale => 'greyscale',
      };

  static GamePalette fromStorageKey(String? key) {
    if (key == 'sea') return GamePalette.glass;
    // Sunglass was folded into Rainbow.
    if (key == 'sunglass') return GamePalette.rainbow;
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
        GamePalette.sunset =>
          true,
        _ => false,
      };

  String get unlockRequirementText => switch (this) {
        GamePalette.world11 => 'Win 1 game',
        GamePalette.neon => 'Win an Easy game under 10 minutes',
        GamePalette.pkmn => 'Win 3 games in a row',
        GamePalette.pkmn2 => 'Win a Hard game with no mistakes',
        GamePalette.glass => 'Win an Expert game with no mistakes',
        GamePalette.sunset => 'Win a Master game',
        _ => '',
      };

  /// Text segments for locked-palette toasts. Highlighted parts are difficulty names.
  List<({String text, bool highlight})> get unlockRequirementParts =>
      switch (this) {
        GamePalette.world11 => const [(text: 'Win 1 game', highlight: false)],
        GamePalette.neon => [
          (text: 'Win an ', highlight: false),
          (text: Difficulty.easy.label, highlight: true),
          (text: ' game under 10 minutes', highlight: false),
        ],
        GamePalette.pkmn => const [
          (text: 'Win 3 games in a row', highlight: false),
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
        GamePalette.sunset => [
          (text: 'Win a ', highlight: false),
          (text: Difficulty.master.label, highlight: true),
          (text: ' game', highlight: false),
        ],
        _ => [(text: unlockRequirementText, highlight: false)],
      };
}
