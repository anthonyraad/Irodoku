class Cell {
  /// Committed color value 1–9, or 0 for empty / notes-only.
  final int value;

  /// Tentative note color values (1–9). Each maps to a fixed 3×3 slot.
  final Set<int> notes;

  final bool isGiven;
  /// True after the player commits the correct solution color (not editable).
  final bool isLocked;
  final bool hasConflict;

  const Cell({
    this.value = 0,
    this.notes = const {},
    this.isGiven = false,
    this.isLocked = false,
    this.hasConflict = false,
  });

  bool get isEmpty => value == 0 && notes.isEmpty;

  bool get hasNotes => notes.isNotEmpty;

  /// Player may change value/notes (not a clue and not a confirmed correct fill).
  bool get isEditable => !isGiven && !isLocked;

  bool hasNote(int colorValue) => notes.contains(colorValue);

  Cell copyWith({
    int? value,
    Set<int>? notes,
    bool? isGiven,
    bool? isLocked,
    bool? hasConflict,
    bool clearValue = false,
    bool clearNotes = false,
  }) {
    final nextValue = clearValue ? 0 : (value ?? this.value);
    return Cell(
      value: nextValue,
      notes: clearNotes ? const {} : (notes ?? this.notes),
      isGiven: isGiven ?? this.isGiven,
      // Clearing the fill always unlocks; otherwise keep/override lock flag.
      isLocked: clearValue ? false : (isLocked ?? this.isLocked),
      hasConflict: hasConflict ?? this.hasConflict,
    );
  }

  Cell withNoteAdded(int colorValue) {
    if (colorValue < 1 || colorValue > 9) return this;
    if (notes.contains(colorValue)) {
      // Already noted — still clear any committed fill.
      return value == 0 ? this : copyWith(clearValue: true);
    }
    return copyWith(
      clearValue: true,
      notes: {...notes, colorValue},
    );
  }

  Cell withNoteRemoved(int colorValue) {
    if (!notes.contains(colorValue)) return this;
    final next = {...notes}..remove(colorValue);
    return copyWith(clearValue: true, notes: next);
  }
}
