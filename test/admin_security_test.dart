import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigator/admin_panel.dart';
import 'package:navigator/security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('first run creates a unique admin with a salted password hash', () async {
    final repository = AdminRepository();
    expect(await repository.hasConfiguredAccounts(), isFalse);
    final account = await repository.createFirstAdmin(
      'navigator-owner',
      'a-long-unique-password-42',
    );
    expect(account, isNotNull);
    expect(account!.role, 'superadmin');
    expect(account.passwordHash, startsWith('v2'));
    expect(PasswordHasher.verify('a-long-unique-password-42', account.passwordHash), isTrue);
    expect(PasswordHasher.verify('wrong-password', account.passwordHash), isFalse);
    expect(await repository.hasConfiguredAccounts(), isTrue);
  });

  test('first-run setup cannot overwrite an existing admin account', () async {
    final repository = AdminRepository();
    final first = await repository.createFirstAdmin('owner-one', 'a-long-unique-password-42');
    final second = await repository.createFirstAdmin('owner-two', 'another-long-password-43');
    expect(first, isNotNull);
    expect(second, isNull);
    expect((await repository.list()).map((e) => e.login), ['owner-one']);
  });

  test('an explicitly empty permission set stays empty after save/load', () async {
    final prefs = await SharedPreferences.getInstance();
    final restricted = AdminAccount(
      id: 'restricted',
      login: 'restricted-user',
      passwordHash: PasswordHasher.secureDigest('a-long-unique-password-42'),
      role: 'admin',
      permissions: const [],
      permissionsConfigured: true,
    );

    await AdminRepository().save([restricted]);
    final loaded = (await AdminRepository().list()).single;

    expect(loaded.permissionsConfigured, isTrue);
    expect(loaded.effectivePermissions, isEmpty);
    expect(loaded.can(AdminPermissions.manageData), isFalse);

    final copied = loaded.copyWith(permissions: const []);
    expect(copied.effectivePermissions, isEmpty);
    expect(prefs.getString('navigator_admins_v2'), isNotNull);
  });

  test('accounts without a configured permission list receive role defaults', () {
    final account = AdminAccount(
      id: 'legacy',
      login: 'legacy-user',
      passwordHash: 'legacy-hash',
      role: 'content',
    );

    expect(account.permissionsConfigured, isFalse);
    expect(account.can(AdminPermissions.manageSchedule), isTrue);
    expect(account.can(AdminPermissions.manageSync), isFalse);
  });

  test('lockout cannot be bypassed by changing login letter case', () async {
    final repository = AdminRepository();
    final account = await repository.createFirstAdmin(
      'CaseSensitiveOwner',
      'a-long-unique-password-42',
    );
    expect(account, isNotNull);

    for (var attempt = 0; attempt < 5; attempt++) {
      expect(
        await repository.authenticate('casesensitiveowner', 'wrong-password'),
        isNull,
      );
    }

    // The correct password with a different casing must remain blocked.
    expect(
      await repository.authenticate('CASESENSITIVEOWNER', 'a-long-unique-password-42'),
      isNull,
    );
  });

  test('corrupt admin storage does not permanently disable first-run setup', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('navigator_admins_v2', '{broken-json');
    final repository = AdminRepository();

    expect(await repository.hasConfiguredAccounts(), isFalse);
    final account = await repository.createFirstAdmin(
      'recovered-owner',
      'a-long-unique-password-42',
    );
    expect(account, isNotNull);
    expect((await repository.list()).single.login, 'recovered-owner');
  });

  test('empty storage has no default admin account', () async {
    expect(await AdminRepository().list(), isEmpty);
  });
}