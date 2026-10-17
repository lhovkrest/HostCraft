# HostCraft: new engines, crossplay and world settings

## pubspec.yaml
```yaml
dependencies:
  file_picker: ^8.0.0     # world zip import
  archive: ^4.0.0         # already used; world backup needs ZipFileEncoder from archive_io
  crypto: ^3.0.0          # already used
```

## Hook the new screens into your UI (hostcraft_app.dart was not uploaded)
```dart
import '../ui/server_setup_sheet.dart';
import '../ui/world_settings_page.dart';

// server type / version / crossplay
onPressed: () => showServerSetup(context),

// world settings
onPressed: () => Navigator.push(context,
    MaterialPageRoute(builder: (_) => const WorldSettingsPage())),
```

## Show the Bedrock address next to the Java one
```dart
final tunnel = host.tunnel;
if (tunnel?.bedrockAddress != null) Text('Bedrock: ${tunnel!.bedrockAddress}  (UDP)');
if (tunnel?.bedrockNote != null) Text(tunnel!.bedrockNote!);
```
Optional "update server files" button: `host.updateServerFiles()`.
