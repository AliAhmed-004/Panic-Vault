import 'package:flutter/foundation.dart';
import '../services/secure_vault_service.dart';

class AuthProvider extends ChangeNotifier {
  SecureVaultService? _vaultService;
  bool _isUnlocked = false;

  SecureVaultService? get vaultService => _vaultService;
  bool get isUnlocked => _isUnlocked;

  void unlockVault(SecureVaultService vaultService) {
    _vaultService = vaultService;
    _isUnlocked = true;
    notifyListeners();
  }

  void lockVault() {
    _vaultService?.lockVault();
    _vaultService = null;
    _isUnlocked = false;
    notifyListeners();
  }

  void logout() {
    lockVault();
  }

  // Get current vault key for password operations
  Uint8List? getCurrentVaultKey() {
    return _vaultService?.getCurrentVaultKey();
  }
}
