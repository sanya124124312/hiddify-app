import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hiddify/features/nexus_home/nexus_home_screen.dart';

/// Root widget for Nexus VPN — replaces Hiddify's App widget.
class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Nexus VPN",
      themeMode: ThemeMode.dark,
      darkTheme: _buildTheme(),
      theme: _buildTheme(),
      home: const NexusHomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF090D18),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF4A9EFF),
        secondary: Color(0xFF7B6EF6),
        surface: Color(0xFF141927),
      ),
      cardColor: const Color(0xFF141927),
      fontFamily: 'Inter',
      useMaterial3: true,
    );
  }
}
