import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;

class PasswordHasher {
  static const int iterations = 40000;

  static String sha256Digest(String value) =>
      crypto.sha256.convert(utf8.encode(value)).toString();

  static String secureDigest(String password) {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    var digest = crypto.sha256.convert([...salt, ...utf8.encode(password)]).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = crypto.sha256.convert([...salt, ...digest]).bytes;
    }
    return 'v2\$' + iterations.toString() + '\$' +
        base64UrlEncode(salt) + '\$' + base64UrlEncode(digest);
  }

  static bool verify(String password, String stored) {
    if (!stored.startsWith('v2\$')) return stored == sha256Digest(password);
    final parts = stored.split('\$');
    if (parts.length != 4) return false;
    final count = int.tryParse(parts[1]);
    if (count == null || count < 1000 || count > 200000) return false;
    try {
      final salt = base64Url.decode(parts[2]);
      var digest = crypto.sha256.convert([...salt, ...utf8.encode(password)]).bytes;
      for (var i = 1; i < count; i++) {
        digest = crypto.sha256.convert([...salt, ...digest]).bytes;
      }
      final expected = base64UrlEncode(digest);
      if (expected.length != parts[3].length) return false;
      var result = 0;
      for (var i = 0; i < expected.length; i++) {
        result |= expected.codeUnitAt(i) ^ parts[3].codeUnitAt(i);
      }
      return result == 0;
    } catch (_) {
      return false;
    }
  }
}

class AdminPermissions {
  static const manageAdmins = 'manage_admins';
  static const manageData = 'manage_data';
  static const manageSchedule = 'manage_schedule';
  static const manageAnnouncements = 'manage_announcements';
  static const manageRooms = 'manage_rooms';
  static const managePlaces = 'manage_places';
  static const manageSync = 'manage_sync';
  static const viewAudit = 'view_audit';
  static const manageSecurity = 'manage_security';

  static const all = <String>{
    manageAdmins, manageData, manageSchedule, manageAnnouncements,
    manageRooms, managePlaces, manageSync, viewAudit, manageSecurity,
  };
}

class AdminAuthStore {
  static const bootstrapLogin = 'admin';
  static const bootstrapPasswordSha256 =
      '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918';
}
