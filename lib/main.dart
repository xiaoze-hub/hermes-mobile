import 'package:flutter/material.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'services/hermes_gateway_service.dart';
import 'ui/chat/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = HermesStorage();
  final config = await storage.loadConfig();

  final gatewayService = HermesGatewayService(
    serverUrl: config.serverUrl,
    token: config.token,
  );

  runApp(HermesMobileApp(gatewayService: gatewayService));
}

class HermesMobileApp extends StatelessWidget {
  final HermesGatewayService gatewayService;

  const HermesMobileApp({super.key, required this.gatewayService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Agent',
      debugShowCheckedModeBanner: false,
      theme: HermesTheme.darkTheme,
      home: ChatScreen(gatewayService: gatewayService),
    );
  }
}
