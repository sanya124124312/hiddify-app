import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/nexus_auth/nexus_auth_gate.dart';

const _baseUrl = "https://getnexus.su";

class NexusHomeScreen extends ConsumerStatefulWidget {
  const NexusHomeScreen({super.key});

  @override
  ConsumerState<NexusHomeScreen> createState() => _NexusHomeScreenState();
}

class _NexusHomeScreenState extends ConsumerState<NexusHomeScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _sub;
  Map<String, dynamic>? _me;
  bool _loadingSub = true;
  String? _subError;
  bool _profileImported = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _loadData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loadingSub = true; _subError = null; });
    try {
      final token = await NexusAuthGate.getToken();
      final headers = {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      };

      final results = await Future.wait([
        http.get(Uri.parse("$_baseUrl/api/me"), headers: headers),
        http.get(Uri.parse("$_baseUrl/api/subscription"), headers: headers),
      ]);

      final meRes = results[0];
      final subRes = results[1];

      if (meRes.statusCode == 200) {
        _me = jsonDecode(utf8.decode(meRes.bodyBytes));
      }
      if (subRes.statusCode == 200) {
        _sub = jsonDecode(utf8.decode(subRes.bodyBytes));
        // Auto-import subscription profile into Hiddify
        if (_sub!["active"] == true && !_profileImported) {
          final subUrl = _sub!["sub_url"] as String?;
          if (subUrl != null && subUrl.isNotEmpty) {
            _importProfile(subUrl);
          }
        }
      }
    } catch (e) {
      _subError = "Ошибка загрузки данных";
    } finally {
      if (mounted) setState(() { _loadingSub = false; });
    }
  }

  Future<void> _importProfile(String subUrl) async {
    try {
      final profileRepo = ref.read(profileRepositoryProvider).requireValue;
      await profileRepo.upsertRemote(subUrl).run();
      _profileImported = true;
    } catch (_) {}
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("nexus_auth_token");
    if (mounted) {
      // Restart the app by relaunching from scratch
      // On Android, exit and let the OS restart
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(connectionNotifierProvider);
    final status = connState.asData?.value ?? const ConnectionStatus.disconnected();

    final isConnected = status is Connected;
    final isConnecting = status is Connecting || status is Disconnecting;

    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF4A9EFF),
          backgroundColor: const Color(0xFF141927),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                _Header(me: _me, onLogout: _logout),
                const SizedBox(height: 28),

                // ── Connection button ──
                _ConnectButton(
                  isConnected: isConnected,
                  isConnecting: isConnecting,
                  pulseAnim: _pulseAnim,
                  onTap: () async {
                    await ref.read(connectionNotifierProvider.notifier).toggleConnection();
                  },
                ),
                const SizedBox(height: 28),

                // ── Subscription card ──
                if (_loadingSub)
                  const _LoadingCard()
                else if (_subError != null)
                  _ErrorCard(error: _subError!, onRetry: _loadData)
                else
                  _SubCard(sub: _sub),
                const SizedBox(height: 16),

                // ── Stats row ──
                if (!_loadingSub && _sub != null)
                  _StatsRow(me: _me, sub: _sub),
                const SizedBox(height: 16),

                // ── Connection status banner ──
                if (isConnected || isConnecting)
                  _StatusBanner(isConnected: isConnected, isConnecting: isConnecting),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.me, required this.onLogout});
  final Map<String, dynamic>? me;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final name = (me?["name"] as String?)?.split(" ").first ?? "Привет";
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Nexus VPN", style: TextStyle(
              color: Color(0xFF4A9EFF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            )),
            Text(name, style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            )),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded, color: Color(0xFF8892A4)),
          tooltip: "Выйти",
        ),
      ],
    );
  }
}

// ── Connect button ───────────────────────────────────────────
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.isConnected,
    required this.isConnecting,
    required this.pulseAnim,
    required this.onTap,
  });
  final bool isConnected;
  final bool isConnecting;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isConnected
        ? const Color(0xFF00D1A0)
        : isConnecting
            ? const Color(0xFFF59E0B)
            : const Color(0xFF4A9EFF);

    final label = isConnected
        ? "Отключить"
        : isConnecting
            ? "Подключение..."
            : "Подключить";

    return Center(
      child: GestureDetector(
        onTap: isConnecting ? null : onTap,
        child: AnimatedBuilder(
          animation: pulseAnim,
          builder: (context, child) {
            final scale = isConnected ? pulseAnim.value : 1.0;
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12),
              border: Border.all(color: color.withOpacity(0.4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: isConnected ? 10 : 0,
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isConnected
                        ? Icons.shield_rounded
                        : Icons.shield_outlined,
                    color: color,
                    size: 64,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

// ── Subscription card ────────────────────────────────────────
class _SubCard extends StatelessWidget {
  const _SubCard({required this.sub});
  final Map<String, dynamic>? sub;

  @override
  Widget build(BuildContext context) {
    final isActive = sub?["active"] == true;
    if (!isActive) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Подписка", style: _labelStyle),
            const SizedBox(height: 8),
            const Text("❌ Нет активной подписки", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _GradientButton(
              label: "Купить подписку →",
              onTap: () {},
            ),
          ],
        ),
      );
    }

    final planLabel = sub?["plan_label"] as String? ?? sub?["plan_key"] ?? "—";
    final daysLeft = sub?["days_left"] ?? 0;
    final server = sub?["server_country"] ?? "";
    final flag = sub?["server_flag"] ?? "🌍";
    final isTrial = sub?["plan_key"] == "trial";

    final expiresAt = sub?["expires_at"] as String?;
    String expiresStr = "";
    if (expiresAt != null) {
      try {
        final dt = DateTime.parse(expiresAt);
        expiresStr = "${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}";
      } catch (_) {}
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("Подписка", style: _labelStyle),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isTrial
                      ? const Color(0xFFF59E0B).withOpacity(0.15)
                      : const Color(0xFF00D1A0).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isTrial
                        ? const Color(0xFFF59E0B).withOpacity(0.3)
                        : const Color(0xFF00D1A0).withOpacity(0.25),
                  ),
                ),
                child: Text(
                  isTrial ? "⏱ Пробный" : "✓ Активна",
                  style: TextStyle(
                    color: isTrial ? const Color(0xFFF59E0B) : const Color(0xFF00D1A0),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _InfoTile(icon: "📅", label: "Тариф", value: planLabel),
              const SizedBox(width: 12),
              _InfoTile(icon: "⏳", label: "Осталось", value: "$daysLeft дн."),
              if (server.isNotEmpty) ...[
                const SizedBox(width: 12),
                _InfoTile(icon: flag, label: "Сервер", value: server),
              ],
            ],
          ),
          if (expiresStr.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              "Истекает $expiresStr",
              style: const TextStyle(color: Color(0xFF8892A4), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Stats row ────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.me, required this.sub});
  final Map<String, dynamic>? me;
  final Map<String, dynamic>? sub;

  @override
  Widget build(BuildContext context) {
    final balance = me?["balance"] ?? 0;
    final devicesUsed = sub?["devices_used"] ?? 0;
    final devicesLimit = sub?["devices_limit"] ?? 3;

    return Row(
      children: [
        Expanded(
          child: _card(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("💰", style: TextStyle(fontSize: 20)),
                const SizedBox(height: 6),
                Text("$balance ₽", style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
                )),
                const Text("Баланс", style: _labelStyle),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _card(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("📱", style: TextStyle(fontSize: 20)),
                const SizedBox(height: 6),
                Text("$devicesUsed / $devicesLimit", style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
                )),
                const Text("Устройства", style: _labelStyle),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Status banner ────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.isConnected, required this.isConnecting});
  final bool isConnected;
  final bool isConnecting;

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? const Color(0xFF00D1A0) : const Color(0xFFF59E0B);
    final text = isConnected ? "🔒 Соединение защищено" : "⏳ Установка соединения...";
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center),
    );
  }
}

// ── Loading card ─────────────────────────────────────────────
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) {
    return _card(
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: Color(0xFF4A9EFF), strokeWidth: 2),
        ),
      ),
    );
  }
}

// ── Error card ───────────────────────────────────────────────
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return _card(
      child: Column(
        children: [
          Text(error, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text("Повторить")),
        ],
      ),
    );
  }
}

// ── Info tile ────────────────────────────────────────────────
class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});
  final String icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(color: Color(0xFF8892A4), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ── Gradient button ──────────────────────────────────────────
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E6FFF), Color(0xFF7B6EF6)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────
Widget _card({required Widget child, EdgeInsets? padding}) {
  return Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF141927),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: child,
  );
}

const _labelStyle = TextStyle(
  color: Color(0xFF8892A4),
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.5,
);
