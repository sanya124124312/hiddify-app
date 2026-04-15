import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

const _baseUrl = "https://getnexus.su";
const _tokenKey = "nexus_auth_token";

/// Checks if user is already authenticated.
/// Returns true if a valid token exists.
class NexusAuthGate {
  static Future<bool> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey) ?? "";
    return token.isNotEmpty;
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) ?? "";
  }
}

/// Standalone Flutter app shown before Hiddify bootstrap.
/// After successful login, calls [onAuthenticated] to launch Hiddify.
class NexusAuthApp extends StatelessWidget {
  const NexusAuthApp({super.key, required this.onAuthenticated});

  final Future<void> Function() onAuthenticated;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D18),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF4A9EFF),
          surface: const Color(0xFF141927),
        ),
      ),
      home: NexusLoginScreen(onAuthenticated: onAuthenticated),
    );
  }
}

class NexusLoginScreen extends StatefulWidget {
  const NexusLoginScreen({super.key, required this.onAuthenticated});
  final Future<void> Function() onAuthenticated;

  @override
  State<NexusLoginScreen> createState() => _NexusLoginScreenState();
}

class _NexusLoginScreenState extends State<NexusLoginScreen> {
  int _tab = 0; // 0 = login, 1 = register
  bool _loading = false;
  String _error = "";

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _error = ""; });

    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passCtrl.text;

    if (email.isEmpty || !email.contains("@")) {
      setState(() { _error = "Введите корректный email"; });
      return;
    }
    if (password.length < 8) {
      setState(() { _error = "Пароль минимум 8 символов"; });
      return;
    }
    if (_tab == 1 && password != _confirmCtrl.text) {
      setState(() { _error = "Пароли не совпадают"; });
      return;
    }

    setState(() { _loading = true; });

    try {
      final endpoint = _tab == 0 ? "/auth/login" : "/auth/register";
      final body = _tab == 0
          ? {"email": email, "password": password}
          : {"email": email, "password": password, "name": _nameCtrl.text.trim()};

      final res = await http.post(
        Uri.parse("$_baseUrl$endpoint"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(utf8.decode(res.bodyBytes));

      if (res.statusCode != 200) {
        setState(() { _error = data["detail"] ?? "Ошибка сервера ${res.statusCode}"; });
        return;
      }

      final token = data["token"] as String? ?? "";
      await NexusAuthGate.saveToken(token);

      // Launch Hiddify
      await widget.onAuthenticated();
    } catch (e) {
      setState(() { _error = "Ошибка соединения: $e"; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4A9EFF);
    const bg = Color(0xFF090D18);
    const card = Color(0xFF141927);
    const muted = Color(0xFF8892A4);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E6FFF), Color(0xFF7B6EF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.shield_rounded, color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Nexus VPN",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Свободный интернет без ограничений",
                    style: TextStyle(color: muted, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Tab switcher
                  Container(
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _tabBtn("Вход", 0),
                        _tabBtn("Регистрация", 1),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Form fields
                  Container(
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Column(
                      children: [
                        if (_tab == 1) ...[
                          _field(_nameCtrl, "Имя (необязательно)", Icons.person_outline_rounded),
                          _divider(),
                        ],
                        _field(_emailCtrl, "Email", Icons.email_outlined, type: TextInputType.emailAddress),
                        _divider(),
                        _field(_passCtrl, "Пароль (мин. 8 символов)", Icons.lock_outline_rounded, obscure: true),
                        if (_tab == 1) ...[
                          _divider(),
                          _field(_confirmCtrl, "Повторите пароль", Icons.lock_outline_rounded, obscure: true),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error,
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // Submit button
                  GestureDetector(
                    onTap: _loading ? null : _submit,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E6FFF), Color(0xFF7B6EF6)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _tab == 0 ? "Войти" : "Создать аккаунт",
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabBtn(String label, int index) {
    final active = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _tab = index; _error = ""; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF4A9EFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white.withOpacity(0.5),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      {bool obscure = false, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: type,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF8892A4), fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF8892A4), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _divider() => Divider(
    height: 1,
    color: Colors.white.withOpacity(0.06),
    indent: 16,
    endIndent: 16,
  );
}
