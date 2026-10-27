import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/features/apps/services/app_icon_loader.dart';

import 'helpers/fakes.dart';

void main() {
  InstalledApp app(String pkg, [int version = 1]) =>
      InstalledApp(packageName: pkg, label: pkg, versionCode: version);

  late FakeEnforcementBridge bridge;
  late AppIconLoader loader;

  setUp(() {
    bridge = FakeEnforcementBridge()
      ..iconPaths = {'a': '/icons/a@1.png', 'b': '/icons/b@1.png'};
    loader = AppIconLoader(bridge);
  });

  test('requests made in the same task go to native as one batch', () async {
    final paths = await Future.wait([
      loader.pathFor(app('a')),
      loader.pathFor(app('b')),
      loader.pathFor(app('c')),
    ]);
    expect(paths, ['/icons/a@1.png', '/icons/b@1.png', null]);
    expect(bridge.iconRequests, [
      ['a', 'b', 'c'],
    ]);
  });

  test('each app version is requested once and then known synchronously',
      () async {
    expect(loader.isResolved(app('a')), isFalse);
    await loader.pathFor(app('a'));
    await loader.pathFor(app('a'));
    expect(bridge.iconRequests, [
      ['a'],
    ]);
    expect(loader.isResolved(app('a')), isTrue);
    expect(loader.resolvedPath(app('a')), '/icons/a@1.png');

    // An updated app has a new icon to fetch.
    await loader.pathFor(app('a', 2));
    expect(bridge.iconRequests.last, ['a']);
  });

  test('requests in later tasks form new batches', () async {
    await loader.pathFor(app('a'));
    await loader.pathFor(app('b'));
    expect(bridge.iconRequests, [
      ['a'],
      ['b'],
    ]);
  });
}
