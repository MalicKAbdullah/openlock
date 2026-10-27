import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/perf_log.dart';
import 'package:openlock/src/core/storage_keys.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';

/// High-level authentication state for opening the OpenLock app itself.
enum AuthStatus { unknown, needsSetup, locked, unlocked }

/// How the current unlocked session was opened.
enum UnlockMethod { pin, biometric, recoveryKey }

/// A pending recovery-key screen: [key] is a freshly created key to show
/// once, or null for the one-time "set up a recovery key" offer. [then] is
/// where the app goes afterwards.
final class RecoveryOffer {
  const RecoveryOffer({required this.then, this.key});

  final String? key;
  final String then;
}

/// Non-null while the router should show the recovery-key screen.
final recoveryOfferProvider = StateProvider<RecoveryOffer?>((_) => null);

/// Whether the first-run intro pages have been seen.
final onboardingSeenProvider = FutureProvider<bool>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  return await storage.read(key: OpenLockKeys.onboardingSeen) == 'true';
});

final class SessionNotifier extends Notifier<AuthStatus> {
  UnlockMethod? _unlockedWith;
  late Future<void> _resolved;
  bool _biometricEnabled = false;
  bool _recoveryOfferDue = false;

  /// How this session was unlocked; null while locked.
  UnlockMethod? get unlockedWith => _unlockedWith;

  /// Completes once the status and the unlock flags below are read.
  Future<void> get resolved => _resolved;

  /// Whether the unlock screen prompts for a fingerprint. Read with the
  /// status, so the prompt can fire on the unlock screen's first frame.
  bool get biometricEnabled => _biometricEnabled;

  @override
  AuthStatus build() {
    _resolved = _resolve();
    return AuthStatus.unknown;
  }

  /// Reads everything the locked → unlocked step needs up front, so nothing
  /// is read between a successful fingerprint and the home screen. The
  /// config is loaded too, so the unlock screen's first frame already has
  /// the keypad order.
  Future<void> _resolve() async {
    final auth = ref.read(pinAuthServiceProvider);
    final (hasPin, biometricEnabled, recoveryOfferDue, _) = await (
      auth.hasPin(),
      ref.read(biometricServiceProvider).isEnabled(),
      auth.recoveryOfferDue(),
      ref.read(configControllerProvider.future),
    ).wait;
    _biometricEnabled = biometricEnabled;
    _recoveryOfferDue = recoveryOfferDue;
    state = hasPin ? AuthStatus.locked : AuthStatus.needsSetup;
  }

  /// Records that the intro pages were seen and refreshes the flag.
  Future<void> completeOnboarding() async {
    await ref
        .read(secureStorageProvider)
        .write(key: OpenLockKeys.onboardingSeen, value: 'true');
    ref.invalidate(onboardingSeenProvider);
  }

  /// First-run PIN creation. Pushes the initial config to native, creates the
  /// recovery key to show once, and unlocks. [then] is where the app goes
  /// after the key is confirmed saved.
  Future<void> completeSetup(String pin, {required String then}) async {
    final auth = ref.read(pinAuthServiceProvider);
    await auth.setupPin(pin);
    await ref.read(configControllerProvider.notifier).pushToNative();
    final key = await auth.createRecoveryKey();
    await auth.markRecoveryOffered();
    ref.read(recoveryOfferProvider.notifier).state =
        RecoveryOffer(key: key, then: then);
    _unlockedWith = UnlockMethod.pin;
    state = AuthStatus.unlocked;
  }

  /// Unlocks; queues the one-time recovery-key offer when it is due.
  void markUnlocked(UnlockMethod method, {required String then}) {
    if (_recoveryOfferDue) {
      ref.read(recoveryOfferProvider.notifier).state =
          RecoveryOffer(then: then);
    }
    _open(method);
  }

  void _open(UnlockMethod method) {
    _unlockedWith = method;
    state = AuthStatus.unlocked;
    PerfLog.mark('unlocked (${method.name})');
  }

  /// Forgotten PIN: a matching recovery key sets [newPin], pushes the new
  /// verifier to native and unlocks.
  Future<UnlockResult> recover({
    required String recoveryKey,
    required String newPin,
  }) async {
    final result = await ref
        .read(pinAuthServiceProvider)
        .resetWithRecoveryKey(recoveryKey: recoveryKey, newPin: newPin);
    if (result is UnlockSuccess) {
      await ref.read(configControllerProvider.notifier).pushToNative();
      // The key was just used, so the offer to create one is moot.
      _open(UnlockMethod.recoveryKey);
    }
    return result;
  }

  /// Whether [changePin] may skip the current PIN: the session was opened
  /// with a fingerprint, which is confirmed again at change time.
  bool get canChangePinWithBiometric => _unlockedWith == UnlockMethod.biometric;

  /// Changes the PIN. Proof is [oldPin], or — when [canChangePinWithBiometric]
  /// and [oldPin] is null — a fresh fingerprint. Pushes the new verifier to
  /// native on success.
  Future<UnlockResult> changePin({
    required String? oldPin,
    required String newPin,
  }) async {
    final auth = ref.read(pinAuthServiceProvider);
    final UnlockResult result;
    if (oldPin == null) {
      final confirmed = canChangePinWithBiometric &&
          await ref
              .read(biometricServiceProvider)
              .confirm('Confirm it’s you to change your PIN');
      if (!confirmed) return const UnlockWrongPin(failedAttempts: 0);
      await auth.setupPin(newPin);
      result = const UnlockSuccess();
    } else {
      result = await auth.changePin(oldPin: oldPin, newPin: newPin);
    }
    if (result is UnlockSuccess) {
      await ref.read(configControllerProvider.notifier).pushToNative();
    }
    return result;
  }

  Future<void> lock() async {
    _unlockedWith = null;
    await _resolve();
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, AuthStatus>(SessionNotifier.new);
