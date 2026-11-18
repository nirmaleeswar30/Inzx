import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The app's secure storage. On iOS the Keychain items stay readable after
/// the first unlock, so background work during locked playback (token
/// refresh, scrobbling) can still reach them; the default (`unlocked`) fails
/// there. Other platforms keep the plugin's defaults.
const inzxSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);
