import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/features/enforcement/services/uninstall_guard.dart';

/// Fixtures mirror the Kotlin UninstallGuardMatchingTest: Pixel (AOSP) and
/// Samsung (One UI) window trees, flattened.
void main() {
  const settings = UninstallGuard.settingsPackage;
  const subSettings = 'com.android.settings.SubSettings';

  bool about(
          String windowPackage, String? windowClass, List<ScreenNode> nodes) =>
      UninstallGuard.isAboutOwnApp(
        windowPackage: windowPackage,
        windowClass: windowClass,
        nodes: nodes,
        ownLabel: 'OpenLock',
        ownPackage: 'dev.abdullah.openlock',
      );

  ScreenNode n(String? viewId, String? text) => (viewId: viewId, text: text);

  List<ScreenNode> pixelAppInfo(String label) => [
        n(null, 'App info'),
        n('com.android.settings:id/entity_header_title', label),
        n('com.android.settings:id/entity_header_summary', 'Installed'),
        n('com.android.settings:id/button2', 'Uninstall'),
        n('android:id/title', 'Storage & cache'),
      ];

  List<ScreenNode> samsungAppInfo(String label) => [
        n(null, 'App info'),
        n('com.android.settings:id/entity_header_title', label),
        n('com.android.settings:id/entity_header_summary', 'Version 1.7.0'),
        n('android:id/title', 'Battery'),
        n('com.android.settings:id/button2', 'Uninstall'),
      ];

  group('App info', () {
    test('guards OpenLock\'s own page on Pixel and Samsung', () {
      expect(about(settings, subSettings, pixelAppInfo('OpenLock')), isTrue);
      expect(
        about(
          settings,
          'com.android.settings.applications.InstalledAppDetailsTop',
          samsungAppInfo('OpenLock'),
        ),
        isTrue,
      );
    });

    test('does not guard other apps\' pages', () {
      expect(about(settings, subSettings, pixelAppInfo('Chrome')), isFalse);
      expect(
        about(
          settings,
          'com.android.settings.applications.InstalledAppDetailsTop',
          samsungAppInfo('WhatsApp'),
        ),
        isFalse,
      );
      expect(
          about(settings, subSettings, pixelAppInfo('OpenLock Pro')), isFalse);
    });
  });

  test('does not guard lists that merely contain OpenLock', () {
    expect(
      about(settings, subSettings, [
        n(null, 'All apps'),
        n('android:id/title', 'Chrome'),
        n('android:id/title', 'OpenLock'),
      ]),
      isFalse,
    );
    expect(
      about('com.google.android.settings.intelligence', null, [
        n('android:id/title', 'OpenLock'),
        n('android:id/summary', 'Apps'),
      ]),
      isFalse,
    );
    expect(
      about(
        settings,
        r'com.android.settings.Settings$DeviceAdminSettingsActivity',
        [
          n('android:id/title', 'Find My Device'),
          n('android:id/title', 'OpenLock'),
        ],
      ),
      isFalse,
    );
  });

  group('device admin', () {
    test('guards OpenLock\'s deactivation screen (Pixel and Samsung)', () {
      expect(
        about(settings, 'com.android.settings.DeviceAdminAdd', [
          n('com.android.settings:id/admin_name', 'OpenLock'),
          n('com.android.settings:id/action_button',
              'Deactivate this device admin app'),
        ]),
        isTrue,
      );
      expect(
        about(settings, 'com.android.settings.DeviceAdminAdd', [
          n(null, 'Device admin app'),
          n('com.android.settings:id/sec_admin_title', 'OpenLock'),
        ]),
        isTrue,
      );
    });

    test('does not guard another admin\'s screen', () {
      expect(
        about(settings, 'com.android.settings.DeviceAdminAdd', [
          n('com.android.settings:id/admin_name', 'Find My Device'),
          n(
              'com.android.settings:id/admin_warning',
              'This admin app is active and allows the app Find My Device to '
                  'perform the following operations:'),
        ]),
        isFalse,
      );
    });
  });

  group('package installer', () {
    test('guards OpenLock\'s uninstall dialog', () {
      expect(
        about('com.google.android.packageinstaller', null, [
          n('android:id/alertTitle', 'OpenLock'),
          n('android:id/message', 'Do you want to uninstall this app?'),
        ]),
        isTrue,
      );
      expect(
        about('com.samsung.android.packageinstaller', null, [
          n('com.samsung.android.packageinstaller:id/message',
              'Uninstall OpenLock?'),
        ]),
        isTrue,
      );
    });

    test('does not guard other apps\' uninstall dialogs', () {
      expect(
        about('com.google.android.packageinstaller', null, [
          n('android:id/alertTitle', 'Chrome'),
          n('android:id/message', 'Do you want to uninstall this app?'),
        ]),
        isFalse,
      );
      expect(
        about('com.samsung.android.packageinstaller', null, [
          n(null, 'Uninstall OpenLockPro?'),
        ]),
        isFalse,
      );
    });
  });

  test('ignores non-candidate packages even when they name OpenLock', () {
    expect(
      about('com.android.chrome', null, [n(null, 'Uninstall OpenLock?')]),
      isFalse,
    );
    expect(
      UninstallGuard.isCandidatePackage('com.samsung.android.packageinstaller'),
      isTrue,
    );
    expect(UninstallGuard.isCandidatePackage('com.android.chrome'), isFalse);
  });
}
