import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../application/services/bluetooth_service.dart';
import '../application/services/notification_service.dart';
import '../application/screens/settings_screen.dart';
import '../application/screens/print_progress_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 알림 서비스 초기화
  await NotificationService().initialize();

  runApp(
    ChangeNotifierProvider(
      create: (context) => BluetoothService(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RPI 3D Printer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: PrintProgressScreen(
        bluetoothService: context.read<BluetoothService>(),
      ),
    );
  }
}
