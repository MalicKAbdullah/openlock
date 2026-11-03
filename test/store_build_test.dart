import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/store_build.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/fakes.dart';

class _CountingUpdates implements IUpdateService {
  int checks = 0;
  @override
  Future<UpdateInfo?> check() async {
    checks++;
    return null;
  }

  @override
  Future<bool> openDownload(UpdateInfo info) async => true;
}

/// Run twice in CI: plain, and with `--dart-define=OFFLYNE_STORE=fdroid`.
void main() {
  test('update requests are made only outside the store build', () async {
    final updates = _CountingUpdates();
    final container = ProviderContainer(
      overrides: [
        updateServiceProvider.overrideWithValue(updates),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(updateCheckProvider.future);
    expect(updates.checks, kStoreBuild ? 0 : 1);
  });
}
