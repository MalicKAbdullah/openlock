import 'package:local_auth/local_auth.dart';

/// Abstraction over the platform biometric prompt so unlock logic is
/// testable without platform channels.
abstract interface class IBiometricAuth {
  /// Whether the device has enrolled biometrics ready to use.
  Future<bool> isAvailable();

  /// Shows the biometric prompt. Returns true when the user authenticated.
  Future<bool> authenticate({required String reason});
}

/// Production implementation backed by the local_auth plugin.
final class LocalAuthBiometric implements IBiometricAuth {
  LocalAuthBiometric([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          // Opening an app is not a payment-style confirmation; without this,
          // Android makes face unlock wait for an extra "Confirm" tap.
          sensitiveTransaction: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
