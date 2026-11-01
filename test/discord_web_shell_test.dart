import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Discord index unlocks audio, drops service workers, busts cache', () {
    final html = File('web_discord/index.html').readAsStringSync();
    expect(html, contains("c.resume()"));
    expect(html, contains('getRegistrations'));
    expect(html, contains('flutter_bootstrap.js?v=__BUILD__'));
    final sh = File('web_discord/build.sh').readAsStringSync();
    expect(sh, contains('main.dart.js?v='));
    expect(sh, contains('_flutter.loader.load({})'));
  });
}
