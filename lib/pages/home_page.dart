import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/password_provider.dart';
import '../models/password_entry.dart';
import 'auth_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // Load passwords when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final passwordProvider = context.read<PasswordProvider>();
      
      // Set the vault key in the password provider
      final vaultKey = authProvider.getCurrentVaultKey();
      if (vaultKey != null) {
        passwordProvider.setVaultKey(vaultKey, type: authProvider.vaultType, encryptionContext: authProvider.encryptionContext);
        passwordProvider.loadPasswords();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panic Vault'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Search functionality coming soon!'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
            tooltip: 'Search Passwords',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Clear vault key from password provider
              context.read<PasswordProvider>().clearVaultKey();
              // Logout from auth provider
              context.read<AuthProvider>().logout();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const AuthPage()),
              );
            },
            tooltip: 'Lock Vault',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey[900]!,
              Colors.grey[800]!,
            ],
          ),
        ),
        child: Consumer<PasswordProvider>(
          builder: (context, passwordProvider, child) {
            if (passwordProvider.isLoading) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              );
            }

            if (passwordProvider.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error,
                      size: 64,
                      color: Colors.red[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error Loading Passwords',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      passwordProvider.error!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => passwordProvider.loadPasswords(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            if (passwordProvider.passwords.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.password,
                      size: 64,
                      color: Colors.blue[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No Passwords Saved',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Add your first password to get started',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[400],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => _addSamplePassword(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Sample Password'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                // Header with password count
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${passwordProvider.passwordCount} Passwords',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _addSamplePassword(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Password'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Password list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: passwordProvider.passwords.length,
                    itemBuilder: (context, index) {
                      final password = passwordProvider.passwords[index];
                      return _buildPasswordCard(context, password, passwordProvider);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPasswordCard(BuildContext context, PasswordEntry password, PasswordProvider provider) {
    final title = password.title.isNotEmpty ? password.title : 'Untitled';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.grey[900],
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.white10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _viewPassword(context, password),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blue[600],
              child: Text(
                title[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    password.username.isNotEmpty ? password.username : 'No username',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (password.url.isNotEmpty)
                    Text(
                      password.url,
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                switch (value) {
                  case 'view':
                    _viewPassword(context, password);
                    break;
                  case 'edit':
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Edit functionality coming soon!'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                    break;
                  case 'delete':
                    _deletePassword(context, password, provider);
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [Icon(Icons.visibility), SizedBox(width: 8), Text('View')],
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [Icon(Icons.edit), SizedBox(width: 8), Text('Edit')],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addSamplePassword(BuildContext context) {
    _showAddPasswordDialog(context);
  }

  void _showAddPasswordDialog(BuildContext context) {
    final titleController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final urlController = TextEditingController();
    final notesController = TextEditingController();
    final tagsController = TextEditingController();
    bool isPasswordVisible = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Add New Password',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.grey[850],
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title field
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Title *',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Username field
                    TextField(
                      controller: usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Username *',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Password field with visibility toggle
                    TextField(
                      controller: passwordController,
                      obscureText: !isPasswordVisible,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Password *',
                        labelStyle: const TextStyle(color: Colors.grey),
                        enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              isPasswordVisible = !isPasswordVisible;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // URL field
                    TextField(
                      controller: urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'URL (optional)',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Notes field
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Tags field
                    TextField(
                      controller: tagsController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Tags (optional, comma-separated)',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Validate required fields
                    if (titleController.text.trim().isEmpty ||
                        usernameController.text.trim().isEmpty ||
                        passwordController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill in all required fields'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // Create password entry
                    final provider = context.read<PasswordProvider>();
                    final newPassword = PasswordEntry(
                      id: provider.generateId(),
                      title: titleController.text.trim(),
                      username: usernameController.text.trim(),
                      password: passwordController.text.trim(),
                      url: urlController.text.trim(),
                      notes: notesController.text.trim(),
                      tags: tagsController.text.trim().isEmpty
                          ? []
                          : tagsController.text.trim().split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList(),
                    );

                    // Add password
                    provider.addPassword(newPassword).then((success) {
                      Navigator.of(context).pop();
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password added successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to add password: ${provider.error}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _viewPassword(BuildContext context, PasswordEntry password) {
    bool showPassword = false;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final title = password.title.isNotEmpty ? password.title : 'Untitled';
            final username = password.username;
            final url = password.url;
            final isEmail = username.contains('@');
            final visiblePassword = showPassword ? password.password : '•' * password.password.length;

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.blue[600],
                    child: Text(title[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        if (url.isNotEmpty)
                          Text(url, style: TextStyle(color: Colors.grey[500], fontSize: 12), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  )
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Username/email row
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline, color: Colors.white),
                    title: Text(
                      username.isNotEmpty ? username : 'No username',
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isEmail)
                          IconButton(
                            tooltip: 'Copy email',
                            icon: const Icon(Icons.alternate_email, color: Colors.white),
                            onPressed: username.isEmpty ? null : () => _copyToClipboard(context, 'Email', username),
                          ),
                        IconButton(
                          tooltip: 'Copy username',
                          icon: const Icon(Icons.content_copy, color: Colors.white),
                          onPressed: username.isEmpty ? null : () => _copyToClipboard(context, 'Username', username),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10),
                  // Password row
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_outline, color: Colors.white),
                    title: Text(
                      visiblePassword,
                      style: const TextStyle(color: Colors.white, letterSpacing: 0.5),
                      overflow: TextOverflow.fade,
                      maxLines: 1,
                      softWrap: false,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: showPassword ? 'Hide password' : 'Show password',
                          icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white),
                          onPressed: () => setState(() => showPassword = !showPassword),
                        ),
                        IconButton(
                          tooltip: 'Copy password',
                          icon: const Icon(Icons.content_copy, color: Colors.white),
                          onPressed: password.password.isEmpty ? null : () => _copyToClipboard(context, 'Password', password.password),
                        ),
                      ],
                    ),
                  ),
                  if (password.notes.isNotEmpty) ...[
                    const Divider(color: Colors.white10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Notes', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        password.notes,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Updated ${_formatDate(password.updatedAt)}', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                      ),
                      if (password.tags.isNotEmpty)
                        Icon(Icons.label_outline, size: 14, color: Colors.grey[500]),
                      if (password.tags.isNotEmpty) const SizedBox(width: 4),
                      if (password.tags.isNotEmpty)
                        Flexible(
                          child: Text(password.tags.join(', '), style: TextStyle(color: Colors.grey[500], fontSize: 11), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _copyToClipboard(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(milliseconds: 1200),
        backgroundColor: Colors.blue[600],
      ),
    );
  }

  

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _deletePassword(BuildContext context, PasswordEntry password, PasswordProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text(
          'Delete Password',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${password.title.isNotEmpty ? password.title : 'Untitled'}"?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              provider.deletePassword(password.id).then((success) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password deleted successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete password: ${provider.error}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              });
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}