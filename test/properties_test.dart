import 'package:flutter_test/flutter_test.dart';
import 'package:hostcraft/core/models.dart';

void main() {
  test('round trips profile including explicit EULA choice', () {
    const profile = ServerProfile(
      name: 'Test world',
      eulaAccepted: true,
      engine: ServerEngine.paper,
      contact: 'owner@example.org',
    );
    expect(ServerProfile.fromJson(profile.toJson()).toJson(), profile.toJson());
    expect(const ServerProfile().eulaAccepted, isFalse);
  });
  test('properties edit preserves comments and unmanaged settings', () {
    const source =
        '# World settings\nserver-port=25565\ncustom-plugin:value\nmotd=old\n';
    final updated = ServerProperties(source)
        .update({'motd': '§aHello = friends', 'online-mode': 'true'});
    expect(updated, contains('# World settings\n'));
    expect(updated, contains('custom-plugin:value\n'));
    expect(updated, contains('server-port=25565\n'));
    expect(ServerProperties(updated).values['motd'], '§aHello = friends');
    expect(ServerProperties(updated).values['online-mode'], 'true');
  });
  test('escaped unicode, newline and backslash survive save', () {
    const value = '§bHello\n世界 😀 C:\\world';
    final text = ServerProperties('').update({'motd': value});
    expect(ServerProperties(text).values['motd'], value);
    expect(text, contains(r'\u00a7'));
  });
  test('replacement removes duplicate keys and handles continuations', () {
    final source = 'motd=one\\\n  two\nmotd=last\n# keep me\n';
    final result = ServerProperties(source).update({'motd': 'New'});
    expect(RegExp('motd=').allMatches(result).length, 1);
    expect(result, contains('# keep me'));
    expect(ServerProperties('motd=one\\\n  two').values['motd'], 'onetwo');
  });
}
