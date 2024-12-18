// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import 'package:provider/provider.dart';
import 'dart:async';  // Timer 클래스를 위한 import 추가

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
      setState(() {});

      // 프린팅 진행 상황에 따른 알림
      final status = widget.bluetoothService.printerStatus;
      if (status.progress == 100) {
        widget.bluetoothService.showNotification(
          '프린팅 완료',
          '3D 프린팅이 완료되었습니다.',
        );
      } else if (status.progress > 0 && status.progress % 25 == 0) {
        // 25%, 50%, 75% 진행 시 알림
        widget.bluetoothService.showNotification(
          '프린팅 진행 상황',
          '프린팅이 ${status.progress.toInt()}% 완료되었습니다.',
        );
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _handleError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _handlePrinterAction(
    BuildContext context,
    Future<void> Function() action,
    String successMessage,
    String failurePrefix,
  ) async {
    try {
      await action();
      // SnackBar 대신 작은 알림 표시
      if (!mounted) return;
      // 알림 삭제
    } catch (e) {
      _handleError('$failurePrefix: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothService>(
      builder: (context, bluetoothService, child) {
        final isConnected = widget.isTestMode || bluetoothService.isConnected();
        final status = widget.isTestMode
            ? PrinterStatus(
                fanSpeed: 50,
                timeLeft: 3600,
                currentFile: 'test_file.gcode',
                progress: 75.0,
                currentLayer: 150,
                totalLayers: 200,
                flowRate: 100.0,
              )
            : bluetoothService.printerStatus;

        if (!isConnected) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('진행 상황'),
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bluetooth_disabled,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    '프린터가 연결되어 있지 않습니다',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '프린터를 연결한 후 다시 시도해주세요',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('진행 상황'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status.currentFile != null)
                  Text('현재 파일: ${status.currentFile}',
                      style: Theme.of(context).textTheme.titleLarge),
                
                const SizedBox(height: 24),
                
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.4,
                  child: _buildProgressIndicator(status.progress / 100),
                ),
                
                const SizedBox(height: 24),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildTemperatureCard(
                      '노즐',
                      widget.isTestMode ? 200.0 : bluetoothService.currentNozzleTemperature,
                      context),
                    _buildTemperatureCard(
                      '베드',
                      widget.isTestMode ? 60.0 : bluetoothService.currentBedTemperature,
                      context),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (bluetoothService.isPaused) {
                            _handlePrinterAction(
                              context,
                              bluetoothService.resumePrint,
                              '프린트가 재개되었습니다',
                              '재개 실패',
                            );
                          } else {
                            _handlePrinterAction(
                              context,
                              bluetoothService.pausePrint,
                              '프린트가 일시정지되었습니다',
                              '일시정지 실패',
                            );
                          }
                        },
                        icon: Icon(bluetoothService.isPaused ? Icons.play_arrow : Icons.pause),
                        label: Text(bluetoothService.isPaused ? '재개' : '일시정지'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('프린트 취소'),
                              content: const Text('정말로 프린트를 취소하시겠습니까?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('아니오'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('예'),
                                ),
                              ],
                            ),
                          );
                          
                          if (confirm == true) {
                            try {
                              await bluetoothService.cancelPrint();
                              if (!mounted) return;
                              scaffoldMessenger.showSnackBar(
                                const SnackBar(content: Text('프린트가 취소되었습니다')),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              scaffoldMessenger.showSnackBar(
                                SnackBar(content: Text('취소 실패: $e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.stop),
                        label: const Text('취소'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold
                    ),
                  ),
                  Text(
                    _formatDuration(widget.bluetoothService.printerStatus.timeLeft),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey[600]
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    
    if (hours == 0 && minutes == 0) {
      return '$remainingSeconds초';
    }
    if (hours == 0) {
      return '$minutes분 $remainingSeconds초';
    }
    return '$hours시간 $minutes분 $remainingSeconds초';
  }

  Widget _buildTemperatureCard(String label, double temperature, BuildContext context) {
    final tempData = widget.bluetoothService.temperatureHistory.isNotEmpty 
        ? widget.bluetoothService.temperatureHistory.last 
        : null;
    
    final targetTemp = label == '노즐' 
        ? (widget.isTestMode ? 200.0 : (tempData?.nozzleTargetTemp ?? 0.0))
        : (widget.isTestMode ? 60.0 : (tempData?.bedTargetTemp ?? 0.0));

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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    children: [
                      TextSpan(text: '${temperature.toStringAsFixed(1)}°'),
                      TextSpan(
                        text: ' / ${targetTemp.toStringAsFixed(1)}°',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color getProgressColor(double progress) {
    return ColorTween(
      begin: Colors.red,
      end: Colors.green,
    ).lerp(progress)!;
  }
}
