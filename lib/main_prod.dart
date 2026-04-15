import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/bootstrap.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/nexus_auth/nexus_auth_gate.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );

  // Nexus auth gate: show login before Hiddify bootstrap
  final authenticated = await NexusAuthGate.checkAuth();
  if (!authenticated) {
    runApp(const NexusAuthApp(
      onAuthenticated: _startHiddify,
    ));
    return;
  }

  return await _startHiddify(widgetsBinding);
}

Future<void> _startHiddify([dynamic widgetsBinding]) async {
  final wb = WidgetsFlutterBinding.ensureInitialized();
  await lazyBootstrap(wb, Environment.prod);
}
