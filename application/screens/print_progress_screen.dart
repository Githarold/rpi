import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import 'dart:async';
import 'package:provider/provider.dart';

class PrintProgressScreen extends StatefulWidget {
  final BluetoothService bluetoothService;
  final bool isTestMode;

  PrintProgressScreen({
    super.key,
    required this.bluetoothService,
    this.isTestMode = false,
  });

  @override
  State<PrintProgressScreen> createState() => PrintProgressScreenState();
}

class PrintProgressScreenState extends State<PrintProgressScreen> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.isTestMode) {
      _startPeriodicUpdate();
    }
  }

  void _startPeriodicUpdate() {
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!widget.bluetoothService.isConnected()) {
        _updateTimer?.cancel();
        return;
      }
      setState(() {});  // 상태 업데이트를 통해 화면 갱신
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothService>(
      builder: (context, bluetoothService, child) {
        final PrinterStatus status = bluetoothService.printerStatus;
        final tempData = bluetoothService.temperatureHistory.isNotEmpty 
            ? bluetoothService.temperatureHistory.last 
            : null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('진행 상황'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() {});
                },
              ),
            ],
          ),
          body: bluetoothService.isConnected()
            ? SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.4,
                        child: _buildProgressIndicator(status.progress / 100),
                      ),
                      const SizedBox(height: 24),
                      _buildStatusDetails(status),
                      const SizedBox(height: 24),
                      _buildTemperatureInfo(tempData),
                      const SizedBox(height: 24),
                      _buildControlButtons(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              )
            : Center(
                child: Text(
                  '프린터가 연결되지 않았습니다.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 18,
                  ),
                ),
              ),
        );
      },
    );
  }

  Widget _buildProgressIndicator(double progress) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double size = constraints.maxWidth * 0.6;
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: size * 0.1,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(getProgressColor(progress)),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '출력 중',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusDetails(PrinterStatus status) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Card(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '예상 ���요 시간',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      Duration(seconds: status.timeLeft).toString().split('.').first,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Card(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '층',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${status.currentLayer} / ${status.totalLayers}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTemperatureInfo(TemperatureData? tempData) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildTemperatureCard('노즐', tempData?.nozzleTemp ?? 0),
        const SizedBox(width: 16),
        _buildTemperatureCard('베드', tempData?.bedTemp ?? 0),
      ],
    );
  }

  Widget _buildTemperatureCard(String label, double temperature) {
    return Expanded(
      child: Card(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$label 온도',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${temperature.toStringAsFixed(1)}°C',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              // 일시정지/재개 로직
            },
            icon: const Icon(Icons.pause),
            label: const Text('일시정지'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              // 중�� 로직
            },
            icon: const Icon(Icons.stop),
            label: const Text('중지'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Color getProgressColor(double progress) {
    return ColorTween(
      begin: Colors.red,
      end: Colors.green,
    ).lerp(progress)!;
  }
}
