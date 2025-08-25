# Panic Vault 🔐

A secure password manager built with Flutter, featuring military-grade encryption and a modern dark UI.

## Features

- **🔒 Military-Grade Security**: AES-GCM encryption with 600,000 PBKDF2 iterations
- **🛡️ Brute Force Protection**: Rate limiting with 5-minute lockout after failed attempts
- **💾 Secure Storage**: Platform-specific secure storage for sensitive data
- **🎨 Modern Dark UI**: Clean, professional interface with gradient backgrounds
- **⚡ Performance Optimized**: Background thread processing for heavy cryptographic operations

## Security Features

- Constant-time comparisons to prevent timing attacks
- Memory clearing of sensitive data after use
- Secure random generation for salts and keys
- Master password verification with secure comparison
- Rate limiting protection against brute force attacks

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

1. **First Launch**: Initialize your vault with a master password (minimum 8 characters)
2. **Unlock**: Enter your master password to access the vault
3. **Security**: The app automatically locks after 5 failed attempts for 5 minutes

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── services/
│   └── secure_vault_service.dart # Core security implementation
├── providers/
│   └── auth_provider.dart       # State management
└── pages/
    ├── auth_page.dart           # Authentication UI
    └── home_page.dart           # Main app interface
```

## Dependencies

- `crypto` & `pointycastle`: Cryptography and security
- `flutter_secure_storage`: Secure data storage
- `provider`: State management
- `sqflite`: Local database

## License

This project is part of a Final Year Project (FYP) implementation.
