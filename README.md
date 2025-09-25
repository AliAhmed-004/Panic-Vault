# Panic Vault 🔐

A secure, offline password manager built with Flutter. Panic Vault uses modern cryptography and careful engineering to protect your data while providing a clean, responsive UI.

## Features

- **🔒 Strong Encryption**: AES-GCM (authenticated encryption) for vault contents and per-field data
- **🧠 Modern Key Derivation**: Argon2id (64 MiB memory, 3 iterations, parallelism 2) to derive keys from your master password
- **🛡️ Brute-Force Protection**: 5 failed attempts trigger a 5-minute lockout
- **💾 Secure Storage**: Uses platform-specific secure storage to store encrypted vault data
- **📥 CSV Import (Generic)**: Import from common CSV exports (e.g., Google Password Manager, Dashlane, etc.) with header auto-detection
- **📤 CSV Export**: Export your passwords as plain-text CSV for portability
- **↕️ Sorting Options**: View passwords by date-added (newest first) or alphabetically (A–Z)
- **🎭 Decoy Vault (Optional)**: Create an alternate vault with a different password
- **⚡ Smooth UX**: Heavy cryptography runs on a background isolate to keep the UI responsive

## Security Architecture

- **Key Derivation**: Argon2id via the `cryptography` package with 64 MiB memory, 3 iterations, and parallelism 2
- **Encryption**: AES-GCM using PointyCastle with a 12-byte IV and 128-bit tag
- **Per-Field Encryption**: Sensitive fields (title, username, password, url, notes, tags) are encrypted individually
- **Additional Authenticated Data (AAD)**: Per-vault context can be used as AAD for additional binding
- **Rate Limiting**: Maximum of 5 attempts, followed by a 5-minute lockout
- **Timing Safety**: Constant-time comparisons to mitigate timing attacks
- **Memory Hygiene**: Sensitive byte arrays are zeroed after use; strings are cleared best-effort where feasible
- **Randomness**: Cryptographically secure random generation for salts, IVs, and keys

## Getting Started

### Prerequisites
- Flutter SDK (^3.8.1)
- Dart SDK

### Installation

1. Clone the repository
2. Navigate to the project directory
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## Usage

- **First Launch**: Initialize your vault with a master password (minimum 8 characters)
- **Unlock**: Enter your master password to access the vault
- **Import (CSV)**: Settings → Import Passwords (CSV). Preview the first 5 entries, then import all.
- **Export (CSV)**: Settings → Export Passwords (plain-text CSV)
- **Sort Order**: Settings → Sort Order → choose Date added (newest first) or Alphabetical (A–Z)
- **Decoy Vault (Optional)**: Tap the app version in Settings multiple times to reveal hidden settings and create a decoy vault

## Project Structure

```
lib/
├── main.dart                         # App entry
├── models/
│   └── password_entry.dart           # Password entry model
├── providers/
│   ├── auth_provider.dart            # Auth + vault state
│   └── password_provider.dart        # Password data + sorting + import flow
├── services/
│   ├── secure_vault_service.dart     # Argon2id, AES-GCM, lockout, memory hygiene
│   ├── password_database_service.dart# Sqflite storage (encrypted fields)
│   ├── password_encryption_service.dart # Per-field AES-GCM
│   ├── csv_import_service.dart       # Generic CSV parsing + mapping
│   └── csv_export_service.dart       # CSV export
└── pages/
    ├── auth_page.dart                # Initialize/unlock UI
    ├── home_page.dart                # Password list, search, view
    └── settings_page.dart            # Import/export, sort order, decoy vault
```

## Dependencies

- `cryptography`: Argon2id key derivation
- `pointycastle`: AES-GCM encryption
- `crypto`: SHA-256 and HMAC utilities
- `flutter_secure_storage`: Platform-specific secure storage
- `sqflite` + `path`: Local database
- `provider`: State management
- `csv`: CSV parsing
- `file_picker`: Cross-platform file picking/saving

