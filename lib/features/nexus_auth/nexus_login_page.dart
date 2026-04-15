import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';

const _baseUrl = "https://getnexus.su";

class NexusLoginPage extends HookConsumerWidget {
  const NexusLoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = useState(0); // 0 = login, 1 = register
    final emailCtrl = useTextEditingController();
    final passCtrl = useTextEditingController();
    final confirmCtrl = useTextEditingController();
    final nameCtrl = useTextEditingController();
    final loading = useState(false);
    final error = useState("");

    Future<void> handleSubmit() async {
      error.value = "";
      final email = emailCtrl.text.trim().toLowerCase();
      final password = passCtrl.text;

      if (email.isEmpty || !email.contains("@")) {
        error.value = "Введите корректный email";
        return;
      }
      if (password.length < 8) {
        error.value = "Пароль минимум 8 символов";
        return;
      }
      if (tabIndex.value == 1 && password != confirmCtrl.text) {
        error.value = "Пароли не совпадают";
        return;
      }

      loading.value = true;
      try {
        final endpoint = tabIndex.value == 0 ? "/auth/login" : "/auth/register";
        final body = tabIndex.value == 0
            ? {"email": email, "password": password}
            : {"email": email, "password": password, "name": nameCtrl.text.trim()};

        final res = await http.post(
          Uri.parse("$_baseUrl$endpoint"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        );

        final data = jsonDecode(utf8.decode(res.bodyBytes));

        if (res.statusCode != 200) {
          error.value = data["detail"] ?? "Ошибка сервера";
          return;
        }

        final token = data["token"] as String? ?? "";

        // Сохраняем токен
        await ref.read(Preferences.nexusAuthToken.notifier).update(token);

        // Получаем ссылку подписки
        final subRes = await http.get(
          Uri.parse("$_baseUrl/api/subscription"),
          headers: {"Authorization": "Bearer $token"},
        );
        if (subRes.statusCode == 200) {
          final subData = jsonDecode(utf8.decode(subRes.bodyBytes));
          final subUrl = subData["sub_url"] as String? ?? "";
          if (subUrl.isNotEmpty) {
            await ref.read(Preferences.nexusSubUrl.notifier).update(subUrl);
            // Автоматически добавляем профиль в Hiddify
            final profileRepo = ref.read(profileRepositoryProvider).requireValue;
            await profileRepo.upsertRemote(subUrl).run();
          }
        }

        if (context.mounted) context.go('/home');
      } catch (e) {
        error.value = "Ошибка соединения. Проверьте интернет.";
      } finally {
        loading.value = false;
      }
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF090D18) : Colors.white;
    final cardColor = isDark ? const Color(0xFF141927) : const Color(0xFFF5F7FA);
    final accentColor = const Color(0xFF4A9EFF);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedColor = isDark ? const Color(0xFF8892A4) : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bgColor,
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
                  Text(
                    "Nexus VPN",
                    style: TextStyle(
                      color: textColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Свободный интернет без ограничений",
                    style: TextStyle(color: mutedColor, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Tab switcher
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _TabBtn(
                          label: "Вход",
                          active: tabIndex.value == 0,
                          accentColor: accentColor,
                          cardColor: cardColor,
                          textColor: textColor,
                          onTap: () { tabIndex.value = 0; error.value = ""; },
                        ),
                        _TabBtn(
                          label: "Регистрация",
                          active: tabIndex.value == 1,
                          accentColor: accentColor,
                          cardColor: cardColor,
                          textColor: textColor,
                          onTap: () { tabIndex.value = 1; error.value = ""; },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Fields
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Column(
                      children: [
                        if (tabIndex.value == 1) ...[
                          _InputField(
                            controller: nameCtrl,
                            hint: "Имя (необязательно)",
                            icon: Icons.person_outline_rounded,
                            mutedColor: mutedColor,
                            textColor: textColor,
                          ),
                          _Divider(isDark: isDark),
                        ],
                        _InputField(
                          controller: emailCtrl,
                          hint: "Email",
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          mutedColor: mutedColor,
                          textColor: textColor,
                        ),
                        _Divider(isDark: isDark),
                        _InputField(
                          controller: passCtrl,
                          hint: "Пароль",
                          icon: Icons.lock_outline_rounded,
                          obscure: true,
                          mutedColor: mutedColor,
                          textColor: textColor,
                        ),
                        if (tabIndex.value == 1) ...[
                          _Divider(isDark: isDark),
                          _InputField(
                            controller: confirmCtrl,
                            hint: "Повторите пароль",
                            icon: Icons.lock_outline_rounded,
                            obscure: true,
                            mutedColor: mutedColor,
                            textColor: textColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Error
                  if (error.value.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error.value,
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading.value ? null : handleSubmit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                      ).copyWith(
                        backgroundColor: WidgetStateProperty.all(Colors.transparent),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E6FFF), Color(0xFF7B6EF6)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: loading.value
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  tabIndex.value == 0 ? "Войти" : "Создать аккаунт",
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
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
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({
    required this.label,
    required this.active,
    required this.accentColor,
    required this.cardColor,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color accentColor;
  final Color cardColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? accentColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : textColor.withOpacity(0.5),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.mutedColor,
    required this.textColor,
    this.obscure = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color mutedColor;
  final Color textColor;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: TextStyle(color: textColor, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: mutedColor, fontSize: 14),
          prefixIcon: Icon(icon, color: mutedColor, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
      indent: 16,
      endIndent: 16,
    );
  }
}
