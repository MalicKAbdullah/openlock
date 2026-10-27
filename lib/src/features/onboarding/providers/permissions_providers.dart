import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';

/// Live snapshot of the special-access permissions the monitor service needs.
/// Refreshed whenever the user returns from a system settings screen.
final class PermissionsController extends AsyncNotifier<PermissionStates> {
  @override
  Future<PermissionStates> build() =>
      ref.watch(enforcementBridgeProvider).getPermissionStates();

  Future<void> refresh() async {
    state = const AsyncLoading<PermissionStates>().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(enforcementBridgeProvider).getPermissionStates(),
    );
  }

  IEnforcementBridge get _bridge => ref.read(enforcementBridgeProvider);

  Future<void> requestUsageAccess() => _bridge.requestUsageAccess();
  Future<void> requestOverlay() => _bridge.requestOverlayPermission();
  Future<void> requestBattery() => _bridge.requestBatteryExemption();
  Future<void> requestNotifications() =>
      _bridge.requestNotificationPermission();
  Future<void> requestNotificationAccess() =>
      _bridge.requestNotificationAccess();
  Future<void> requestScreenGuardAccess() => _bridge.requestScreenGuardAccess();

  Future<void> startService() async {
    await _bridge.startService();
    await refresh();
  }

  Future<void> stopService() async {
    await _bridge.stopService();
    await refresh();
  }
}

final permissionsControllerProvider =
    AsyncNotifierProvider<PermissionsController, PermissionStates>(
  PermissionsController.new,
);
