import 'package:flutter/material.dart';
import 'gcode_management_screen.dart';
import 'print_progress_screen.dart';
import 'settings_screen.dart';
import 'printer_connection_screen.dart';
import 'info_screen.dart';
import 'temperature_dashboard_screen.dart';
import '../services/bluetooth_service.dart';
import 'dart:async';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  final BluetoothService bluetoothService;

  const HomeScreen({super.key, required this.bluetoothService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _updateTimer;
  final Duration _updateInterval = const Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _startPeriodicUpdate();
  }

  void _startPeriodicUpdate() {
    _updateTimer = Timer.periodic(_updateInterval, (timer) async {
      await updatePrinterStatus();
    });
  }

  Future<void> updatePrinterStatus() async {
    if (widget.bluetoothService.isConnected()) {
      try {
        double nozzle = await widget.bluetoothService.getTemperature('nozzle');
        double bed = await widget.bluetoothService.getTemperature('bed');
        if (mounted) {
          setState(() {
            widget.bluetoothService.updateTemperatures(nozzle, bed);
          });
        }
      } catch (e) {
        print('온도 업데이트 중 오류 발생: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothService>(
      builder: (context, bluetoothService, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('과즙 MIE'),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const InfoScreen()),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildPrinterStatusCard(context),
                          const SizedBox(height: 16),
                          _buildQuickActionsGrid(context),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!widget.bluetoothService.isConnected())
                    _buildTemperatureDashboardButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrinterStatusCard(BuildContext context) {
    bool isConnected = widget.bluetoothService.isConnected();
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('프린터 상태', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                _buildStatusChip(widget.bluetoothService.connectionStatus),
              ],
            ),
            const SizedBox(height: 24),
            if (isConnected) ...[
              _buildTemperatureRow('노즐 온도', widget.bluetoothService.currentTemperature, 250),
              const SizedBox(height: 16),
              _buildTemperatureRow('베드 온도', widget.bluetoothService.currentBedTemperature, 100),
              const SizedBox(height: 24),
              Text('프린터 모델: 과즙 MIE V1', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Text('펌웨어: Marlin 2.1.2.4', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              _buildTemperatureDashboardButton(),
            ] else
              Text('프린터에 연결되어 있지 않습니다.', style: TextStyle(color: Colors.red, fontSize: 18)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case '연결됨':
        color = Colors.green;
        break;
      case '연결 중':
        color = Colors.orange;
        break;
      default:
        color = Colors.red;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }

  Widget _buildTemperatureRow(String label, double? temperature, double maxTemp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 16)),
            Text(
              temperature != null ? '${temperature.toStringAsFixed(1)}°C' : '-- °C',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        SizedBox(height: 8),
        _buildTemperatureBar(temperature, maxTemp),
      ],
    );
  }

  Widget _buildTemperatureBar(double? temperature, double maxTemp) {
    final double progress = (temperature ?? 0) / maxTemp;
    return Stack(
      children: [
        Container(
          height: 10,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: _getTemperatureColor(progress),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ],
    );
  }

  Color _getTemperatureColor(double progress) {
    if (progress < 0.3) return Colors.blue;
    if (progress < 0.7) return Colors.green;
    return Colors.red;
  }

  Widget _buildQuickActionsGrid(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildQuickActionCard(context, '새 프린트 시작', Icons.play_arrow, Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GCodeManagementScreen())))),
              SizedBox(width: 16),
              Expanded(child: _buildQuickActionCard(context, '진행 중인 프린트', Icons.assessment, Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PrintProgressScreen())))),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildQuickActionCard(context, '설정', Icons.settings, Colors.grey, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen())))),
              SizedBox(width: 16),
              Expanded(child: _buildQuickActionCard(context, '프린터 연결', Icons.bluetooth, Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PrinterConnectionScreen())))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap, {bool isWide = false}) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(isWide ? 24.0 : 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isWide ? 64 : 48, color: Colors.white),
              SizedBox(height: isWide ? 24 : 16),
              Text(
                title,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isWide ? 20 : 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    widget.bluetoothService.disconnect();
    super.dispose();
  }

  Widget _buildTemperatureDashboardButton() {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TemperatureDashboardScreen()),
        );
      },
      icon: Icon(Icons.thermostat),
      label: Text('온도 대시보드'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
