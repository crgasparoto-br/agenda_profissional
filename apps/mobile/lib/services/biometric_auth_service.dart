import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricCredentials {
  const BiometricCredentials({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}

class BiometricAuthService {
  BiometricAuthService({
    LocalAuthentication? localAuthentication,
    FlutterSecureStorage? secureStorage,
  })  : _localAuth = localAuthentication ?? LocalAuthentication(),
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const _emailKey = 'biometric_email';
  static const _passwordKey = 'biometric_password';

  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;

  Future<bool> isAvailable() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!isSupported || !canCheckBiometrics) return false;

      final enrolledBiometrics = await _localAuth.getAvailableBiometrics();
      return enrolledBiometrics.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    final email = await _secureStorage.read(key: _emailKey);
    final password = await _secureStorage.read(key: _passwordKey);
    return (email?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);
  }

  Future<void> enable({
    required String email,
    required String password,
  }) async {
    await _secureStorage.write(key: _emailKey, value: email);
    await _secureStorage.write(key: _passwordKey, value: password);
  }

  Future<void> disable() async {
    await _secureStorage.delete(key: _emailKey);
    await _secureStorage.delete(key: _passwordKey);
  }

  Future<BiometricCredentials?> authenticateAndLoadCredentials() async {
    final authenticated = await authenticate();
    if (!authenticated) return null;

    final email = await _secureStorage.read(key: _emailKey);
    final password = await _secureStorage.read(key: _passwordKey);
    if (email == null || password == null) return null;

    return BiometricCredentials(email: email, password: password);
  }

  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Confirme sua identidade para entrar no app',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
