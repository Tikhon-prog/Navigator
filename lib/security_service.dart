import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;

/// Password security for the local prototype.
///
/// New passwords use a per-account salt and repeated SHA-256 derivation.
/// This is still not a substitute for a server-side password KDF such as
/// Argon2id/bcrypt/scrypt; the APK is client-side and can be reverse engineered.
class PasswordHasher {
  static const int iterations = 40000;
  static String sha256(String value) => sha256Digest(value);

  static String sha256Digest(String value) {
    final bytes = utf8.encode(value);
    return crypto.sha256.convert(bytes).toString();
  }

  static String secureDigest(String password) {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    var data = [...salt, ...utf8.encode(password)];
    var digest = crypto.sha256.convert(data).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = crypto.sha256.convert([...salt, ...digest]).bytes;
    }
    return 'v2\$${iterations}\$${base64UrlEncode(salt)}\$${base64UrlEncode(digest)}';
  }

  static bool verify(String password, String stored) {
    if (!stored.startsWith('v2\$')) {
      return stored == sha256Digest(password);
    }
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
      return _constantTimeEquals(base64UrlEncode(digest), parts[3]);
    } catch (_) {
      return false;
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

class AdminAccount {
  final String id;
  final String login;
  final String passwordHash;
  final String role;
  final bool active;
  final List<String> permissions;

  const AdminAccount({
    required this.id,
    required this.login,
    required this.passwordHash,
    required this.role,
    this.active = true,
    this.permissions = const [],
  });

  List<String> get effectivePermissions =>
      permissions.isNotEmpty ? List.unmodifiable(permissions) : AdminPermissions.forRole(role);

  bool can(String permission) =>
      role == 'superadmin' || effectivePermissions.contains(permission);

  AdminAccount copyWith({
    String? login,
    String? passwordHash,
    String? role,
    bool? active,
    List<String>? permissions,
  }) =>
      AdminAccount(
        id: id,
        login: login ?? this.login,
        passwordHash: passwordHash ?? this.passwordHash,
        role: role ?? this.role,
        active: active ?? this.active,
        permissions: permissions ?? this.permissions,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'login': login,
        'password_hash': passwordHash,
        'role': role,
        'active': active,
        'permissions': effectivePermissions,
      };

  factory AdminAccount.fromJson(Map<String, dynamic> json) {
    final raw = json['permissions'];
    final permissions = raw is List
        ? raw.map((e) => '$e').where((e) => AdminPermissions.all.contains(e)).toSet().toList()
        : <String>[];
    return AdminAccount(
      id: '${json['id'] ?? ''}',
      login: '${json['login'] ?? ''}',
      passwordHash: '${json['password_hash'] ?? ''}',
      role: '${json['role'] ?? 'admin'}',
      active: json['active'] != false,
      permissions: permissions,
    );
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
    manageAdmins,
    manageData,
    manageSchedule,
    manageAnnouncements,
    manageRooms,
    managePlaces,
    manageSync,
    viewAudit,
    manageSecurity,
  };

  static List<String> forRole(String role) {
    switch (role) {
      case 'superadmin':
        return all.toList();
      case 'content':
        return [
          manageData,
          manageSchedule,
          manageAnnouncements,
          manageRooms,
          managePlaces,
          viewAudit,
        ];
      default:
        return [
          manageData,
          manageSchedule,
          manageAnnouncements,
          manageRooms,
          managePlaces,
          manageSync,
          viewAudit,
        ];
    }
  }

  static const labels = <String, String>{
    manageAdmins: 'Управление администраторами',
    manageData: 'Управление данными',
    manageSchedule: 'Расписание',
    manageAnnouncements: 'Объявления',
    manageRooms: 'Кабинеты',
    managePlaces: 'Места и маршруты',
    manageSync: 'Синхронизация API',
    viewAudit: 'Журнал аудита',
    manageSecurity: 'Безопасность и блокировки',
  };
}

