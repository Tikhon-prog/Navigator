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
    expect(account.passwordHash, startsWith('v2\);
    expect(PasswordHasher.verify(
      'a-long-unique-password-42',
      account.passwordHash,
    ), isTrue);
    expect(PasswordHasher.verify('wrong-password', account.passwordHash), isFalse);
    expect(await repository.hasConfiguredAccounts(), isTrue);
  });

  test('first-run setup cannot overwrite an existing admin account', () async {
    final repository = AdminRepository();
    final first = await repository.createFirstAdmin(
      'owner-one',
      'a-long-unique-password-42',
    );
    final second = await repository.createFirstAdmin(
      'owner-two',
      'another-long-password-43',
    );

    expect(first, isNotNull);
    expect(second, isNull);
    expect((await repository.list()).map((e) => e.login), ['owner-one']);
  });

  test('empty storage has no default admin account', () async {
    expect(await AdminRepository().list(), isEmpty);
  });
}
));
    expect(PasswordHasher.verify(
      'a-long-unique-password-42',
      account.passwordHash,
    ), isTrue);
    expect(PasswordHasher.verify('wrong-password', account.passwordHash), isFalse);
    expect(await repository.hasConfiguredAccounts(), isTrue);
  });

  test('first-run setup cannot overwrite an existing admin account', () async {
    final repository = AdminRepository();
    final first = await repository.createFirstAdmin(
      'owner-one',
      'a-long-unique-password-42',
    );
    final second = await repository.createFirstAdmin(
      'owner-two',
      'another-long-password-43',
    );

    expect(first, isNotNull);
    expect(second, isNull);
    expect((await repository.list()).map((e) => e.login), ['owner-one']);
  });

  test('empty storage has no default admin account', () async {
    expect(await AdminRepository().list(), isEmpty);
  });
}
