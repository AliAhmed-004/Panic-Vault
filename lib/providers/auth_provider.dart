import 'package:flutter/foundation.dart';
import '../services/secure_vault_service.dart';

class AuthProvider extends ChangeNotifier {
  SecureVaultService? _vaultService;
  bool _isUnlocked = false;
  VaultType? _vaultType;
  Uint8List? _encryptionContext;

  SecureVaultService? get vaultService => _vaultService;
  bool get isUnlocked => _isUnlocked;
  VaultType? get vaultType => _vaultType;
  Uint8List? get encryptionContext => _encryptionContext;

  void unlockVault(SecureVaultService vaultService) {
    _vaultService = vaultService;
    _isUnlocked = true;
    _vaultType = vaultService.getCurrentVaultType();
    _encryptionContext = vaultService.getCurrentEncryptionContext();
    notifyListeners();
  }

  void lockVault() {
    _vaultService?.lockVault();
    _vaultService = null;
    _isUnlocked = false;
    _vaultType = null;
    _encryptionContext = null;
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
