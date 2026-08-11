// Generates precomputed Master puzzles into assets/sudoku/master_boards.bin
//
// Usage:
//   dart run tool/generate_master_boards.dart
//   dart run tool/generate_master_boards.dart --count=12000 --workers=8
//
// Resumes if the output file already has a valid partial bank.

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/sudoku/master_board_codec.dart';
import 'package:irodoku/sudoku/sudoku_generator.dart';

const _defaultCount = 12000;
const _defaultWorkers = 8;
/// Boards each worker produces per round (keeps checkpoints frequent).
const _chunkPerWorker = 40;
const _outPath = 'assets/sudoku/master_boards.bin';

Future<void> main(List<String> args) async {
  final count = _argInt(args, 'count', _defaultCount);
  final workers = _argInt(args, 'workers', _defaultWorkers);

  final outFile = File(_outPath);
  await outFile.parent.create(recursive: true);

  final collected = <(List<int>, List<int>)>[];
  final seen = <String>{};

  if (await outFile.exists()) {
    try {
      final bytes = await outFile.readAsBytes();
      final bank = MasterBoardCodec.decode(Uint8List.fromList(bytes));
      for (var i = 0; i < bank.count; i++) {
        final boards = bank.boardAt(i);
        final key = boards[0].join(',');
        if (seen.add(key)) {
          collected.add((boards[0], boards[1]));
        }
      }
      stdout.writeln('Resuming with ${collected.length} boards from $_outPath');
    } catch (e) {
      stdout.writeln('Could not resume existing file ($e); starting fresh.');
    }
  }

  if (collected.length >= count) {
    stdout.writeln('Already have ${collected.length} ≥ $count. Done.');
    return;
  }

  stdout.writeln(
    'Generating Master boards with $workers workers '
    '(${_chunkPerWorker}/worker/round, target $count)...',
  );

  final sw = Stopwatch()..start();
  var duplicates = 0;
  var round = 0;

  while (collected.length < count) {
    round++;
    final remaining = count - collected.length;
    final activeWorkers =
        min(workers, max(1, (remaining / _chunkPerWorker).ceil()));
    final futures = <Future<List<(List<int>, List<int>)>>>[];

    for (var w = 0; w < activeWorkers; w++) {
      final seed = Random().nextInt(1 << 30) ^
          (w * 9973) ^
          (round * 7919) ^
          sw.elapsedMicroseconds;
      final chunk = min(_chunkPerWorker, remaining);
      futures.add(Isolate.run(() => _workerGenerate(chunk, seed)));
    }

    for (final future in futures) {
      final batch = await future;
      for (final board in batch) {
        if (collected.length >= count) break;
        final key = board.$1.join(',');
        if (!seen.add(key)) {
          duplicates++;
          continue;
        }
        if (!MasterBoardCodec.validateRecord(board.$1, board.$2)) {
          stderr.writeln('Skipping invalid generated board');
          continue;
        }
        collected.add(board);
      }
    }

    final elapsedSec = sw.elapsedMilliseconds / 1000.0;
    final rate = collected.length / (elapsedSec < 0.001 ? 0.001 : elapsedSec);
    stdout.writeln(
      '  ${collected.length} / $count  '
      '(${rate.toStringAsFixed(1)} boards/s, $duplicates dupes, round $round)',
    );
    await _writeBank(outFile, collected);
  }

  final finalBoards = collected.take(count).toList();
  await _writeBank(outFile, finalBoards);
  final kb = (await outFile.length()) / 1024;
  stdout.writeln(
    'Wrote ${finalBoards.length} boards → $_outPath '
    '(${kb.toStringAsFixed(0)} KB) in '
    '${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
    '($duplicates duplicates skipped)',
  );
}

Future<void> _writeBank(
  File outFile,
  List<(List<int>, List<int>)> boards,
) async {
  final bytes = MasterBoardCodec.encode(boards);
  await outFile.writeAsBytes(bytes, flush: true);
}

List<(List<int>, List<int>)> _workerGenerate(int count, int seed) {
  final rng = Random(seed);
  final out = <(List<int>, List<int>)>[];
  final localSeen = <String>{};
  var attempts = 0;
  while (out.length < count && attempts < count * 40) {
    attempts++;
    final board = _generateOne(rng);
    final key = board.$1.join(',');
    if (!localSeen.add(key)) continue;
    out.add(board);
  }
  return out;
}

(List<int>, List<int>) _generateOne(Random rng) {
  final generated = SudokuGenerator(random: rng).generate(Difficulty.master);
  return (generated.puzzle.toFlat(), generated.solution.toFlat());
}

int _argInt(List<String> args, String name, int fallback) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return int.parse(arg.substring(prefix.length));
    }
  }
  return fallback;
}

int min(int a, int b) => a < b ? a : b;
int max(int a, int b) => a > b ? a : b;
