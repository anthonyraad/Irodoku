# Irodoku

A Flutter Sudoku game that uses **colors instead of numbers**.

## Features

- Fresh randomly generated 9×9 color Sudoku puzzles (backtracking solver + uniqueness checks)
- Easy / Medium / Hard difficulty (configured in Settings)
- Light and dark themes
- Real-time conflict highlighting
- Win streak and completion-time stats
- Local persistence via `shared_preferences`

## Color palette

| # | Color   | Hex     |
|---|---------|---------|
| 1 | Red     | #E53935 |
| 2 | Orange  | #FB8C00 |
| 3 | Yellow  | #FDD835 |
| 4 | Forest green | #2E7D32 |
| 5 | Light blue   | #42A5F5 |
| 6 | Indigo  | #3949AB |
| 7 | Violet  | #8E24AA |
| 8 | Light pink | #F48FB1 |
| 9 | Gray    | #757575 |

## Project structure

```
lib/
  core/           # Palette and themes
  models/         # Difficulty, Cell, GameStats
  sudoku/         # Board, solver, generator
  services/       # Preferences / persistence
  providers/      # Provider state (settings, stats, game)
  screens/        # Game, Settings, Stats
  widgets/        # Grid, cells, color picker, timer, win dialog
```

## Run

```bash
flutter pub get
flutter run
```

## Web / GitHub Pages

Play online at [https://anthonyraad.github.io/Irodoku/](https://anthonyraad.github.io/Irodoku/) after deployment.

Build locally:

```bash
flutter build web --release --base-href="/Irodoku/"
```

Pushes to `main` deploy automatically via GitHub Actions (`.github/workflows/deploy-pages.yml`). Enable **Settings → Pages → Source: GitHub Actions** on the repo if needed.

## Test

```bash
flutter test
```
