import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import 'dart:math';
import 'dart:async';

class PrintProgressScreen extends StatefulWidget {
  final bool isTestMode;

  const PrintProgressScreen({super.key, this.isTestMode = true});

  @override
  State<PrintProgressScreen> createState() => PrintProgressScreenState();
}

class PrintProgressScreenState extends State<PrintProgressScreen> {
  double progress = 0.0;
  String status = '출력 중';
  int currentLayer = 0;
  int totalLayers = 100;
  double nozzleTemp = 200.5;
  double bedTemp = 60.0;
  bool isConnected = true;
  final BluetoothService _bluetoothService = BluetoothService();
  bool isPaused = false;
  Timer? _updateTimer;
  final Random _random = Random();
  double nozzleTargetTemp = 200.0;
  double bedTargetTemp = 60.0;

  @override
  void initState() {
    super.initState();
    if (!widget.isTestMode) {
      _checkPrinterConnection();
    }
    _updateRandomValues();
    _startPeriodicUpdate();
  }

  void _startPeriodicUpdate() {
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _updateRandomValues();
    });
  }

  void _updateRandomValues() {
    setState(() {
      progress = _random.nextDouble();
      currentLayer = (progress * totalLayers).round();
      
      // 노즐 온도 업데이트
      if (nozzleTemp < nozzleTargetTemp) {
        nozzleTemp = min(nozzleTemp + 5, nozzleTargetTemp);
      } else {
        nozzleTemp = nozzleTargetTemp + (_random.nextDouble() - 0.5) * 2;
      }
      
      // 베드 온도 업데이트
      if (bedTemp < bedTargetTemp) {
        bedTemp = min(bedTemp + 2, bedTargetTemp);
      } else {
        bedTemp = bedTargetTemp + (_random.nextDouble() - 0.5) * 1;
      }
    });
  }

  Future<void> _checkPrinterConnection() async {
    const String printerAddress = '00:00:00:00:00:00';
    bool connected = await _bluetoothService.connectToPrinter(printerAddress);
    setState(() {
      isConnected = connected;
    });
  }

  Color getProgressColor(double progress) {
    return ColorTween(
      begin: Colors.red,
      end: Colors.green,
    ).lerp(progress)!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('진행 상황'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // 진행 상황 새로고침 로직
            },
          ),
        ],
      ),
      body: isConnected
          ? SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.4,
                      child: _buildProgressIndicator(),
                    ),
                    const SizedBox(height: 24),
                    _buildStatusDetails(),
                    const SizedBox(height: 24),
                    _buildTemperatureInfo(),
                    const SizedBox(height: 24),
                    _buildControlButtons(),
                    const SizedBox(height: 24), // 추가 여백
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
  }

  Widget _buildProgressIndicator() {
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
                    status,
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

  Widget _buildStatusDetails() {
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
                      '예상 소요 시간',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '2h 15m',
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
                      '$currentLayer / $totalLayers',
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

  Widget _buildTemperatureInfo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildTemperatureCard('노즐', nozzleTemp),
        _buildTemperatureCard('베드', bedTemp),
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
              setState(() {
                isPaused = !isPaused;
              });
              // 일시정지/재개 로직
            },
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
            label: Text(isPaused ? '재시작' : '일시정지'),
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
              // 중지 로직
            },
            icon: const Icon(Icons.stop),
            label: const Text('중지'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError, // 글씨 색상 변경
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}
