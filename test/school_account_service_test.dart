import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/school_account_service.dart';

void main() {
  group('SchoolAccountService.resolveDevicePlatform', () {
    test('maps supported native platforms accurately', () {
      expect(
        SchoolAccountService.resolveDevicePlatform(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        'android',
      );
      expect(
        SchoolAccountService.resolveDevicePlatform(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        'ios',
      );
      expect(
        SchoolAccountService.resolveDevicePlatform(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ),
        'macos',
      );
    });

    test('keeps web push disabled until VAPID and messaging worker are configured', () {
      expect(
        SchoolAccountService.resolveDevicePlatform(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isNull,
      );
    });

    test('does not attempt FCM on unsupported native desktop platforms', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          SchoolAccountService.resolveDevicePlatform(
            isWeb: false,
            platform: platform,
          ),
          isNull,
          reason: '$platform should not initialize Firebase Messaging',
        );
      }
    });
  });
}
