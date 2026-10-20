import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/features/enforcement/services/uninstall_guard.dart';

void main() {
  bool guard({
    required bool preventUninstall,
    required String package,
    String? className,
  }) =>
      UninstallGuard.shouldGuard(
        preventUninstall: preventUninstall,
        package: package,
        className: className,
      );

  test('never guards when protection is off', () {
    expect(
      guard(
        preventUninstall: false,
        package: 'com.android.settings',
        className: 'com.android.settings.DeviceAdminAdd',
      ),
      isFalse,
    );
    expect(
      guard(preventUninstall: false, package: 'com.android.packageinstaller'),
      isFalse,
    );
  });

  group('with protection on', () {
    test('guards the package installer (uninstall dialog)', () {
      expect(
          guard(
              preventUninstall: true, package: 'com.android.packageinstaller'),
          isTrue);
      expect(
        guard(
            preventUninstall: true,
            package: 'com.google.android.packageinstaller'),
        isTrue,
      );
      expect(
        guard(preventUninstall: true, package: 'com.miui.packageinstaller'),
        isTrue,
      );
    });

    test('guards the device-admin deactivation screen', () {
      expect(
        guard(
          preventUninstall: true,
          package: 'com.android.settings',
          className: 'com.android.settings.DeviceAdminAdd',
        ),
        isTrue,
      );
      expect(
        guard(
          preventUninstall: true,
          package: 'com.android.settings',
          className: 'com.android.settings.deviceadmin.DeviceAdminSettings',
        ),
        isTrue,
      );
    });

    test('guards the app-info / uninstall screen', () {
      expect(
        guard(
          preventUninstall: true,
          package: 'com.android.settings',
          className: 'com.android.settings.applications.InstalledAppDetailsTop',
        ),
        isTrue,
      );
    });

    test('does not guard ordinary settings screens', () {
      expect(
        guard(
          preventUninstall: true,
          package: 'com.android.settings',
          className: 'com.android.settings.wifi.WifiSettings',
        ),
        isFalse,
      );
    });

    test('settings package with an unknown class is not guarded', () {
      expect(
        guard(preventUninstall: true, package: 'com.android.settings'),
        isFalse,
      );
    });

    test('unrelated foreground apps are never guarded', () {
      expect(
        guard(
          preventUninstall: true,
          package: 'com.some.chat',
          className: 'com.some.chat.MainActivity',
        ),
        isFalse,
      );
    });
  });
}
