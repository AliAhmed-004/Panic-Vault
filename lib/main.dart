import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:panic_vault/providers/auth_provider.dart';
import 'package:panic_vault/providers/password_provider.dart';
import 'package:panic_vault/pages/auth_page.dart';

void main() {
  runApp(const PanicVault());
}

class PanicVault extends StatelessWidget {
  const PanicVault({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (context) => PasswordProvider()),
      ],
      child: MaterialApp(
        title: 'Panic Vault',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.grey[900],
        ),
        home: const AuthPage(),
      ),
    );
  }
}