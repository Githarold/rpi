import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
import 'package:intl/intl.dart';

class TemperatureDashboardScreen extends StatefulWidget {
  const TemperatureDashboardScreen({super.key});

  @override
  State<TemperatureDashboardScreen> createState() => _TemperatureDashboardScreenState();
}

class _TemperatureDashboardScreenState extends State<TemperatureDashboardScreen> {
  final DateFormat _timeFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('온도 대시보드'),
      ),
      body: Consumer<BluetoothService>(
        builder: (context, bluetoothService, child) {
          final temperatureHistory = bluetoothService.temperatureHistory;
          final nozzleSpots = _createSpots(temperatureHistory, (data) => data.nozzleTemp);
          final bedSpots = _createSpots(temperatureHistory, (data) => data.bedTemp);

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionStatus(bluetoothService.isConnected()),
                _buildTemperatureInfo('노즐 온도', bluetoothService.currentTemperature),
                _buildTemperatureInfo('베드 온도', bluetoothService.currentBedTemperature),
                const SizedBox(height: 20),
                _buildLegend(),
                const SizedBox(height: 20),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 300,
                      minX: 0,
                      maxX: 3600,
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 600, // 10분 간격
                            getTitlesWidget: (value, meta) {
                              final time = DateTime.now().subtract(Duration(seconds: 3600 - value.toInt()));
                              return Text(_timeFormat.format(time));
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          axisNameWidget: const Text('온도 (°C)'),
                          axisNameSize: 24,
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 50,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const Text('');
                              return Text('${value.toInt()}°C');
                            },
                          ),
                        ),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawHorizontalLine: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.grey[300],
                            strokeWidth: 1,
                          );
                        },
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey[400]!, width: 1),
                          left: BorderSide(color: Colors.grey[400]!, width: 1),
                        ),
                      ),
                      lineBarsData: [
                        _createLineChartBarData(nozzleSpots, Colors.red),
                        _createLineChartBarData(bedSpots, Colors.blue),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<FlSpot> _createSpots(List<TemperatureData> history, double Function(TemperatureData) getTemp) {
    final now = DateTime.now();
    return history.map((data) {
      final secondsAgo = now.difference(data.time).inSeconds;
      return FlSpot(3600 - secondsAgo.toDouble(), getTemp(data));
    }).toList();
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLegendItem('노즐 온도', Colors.red),
          const SizedBox(width: 20),
          _buildLegendItem('베드 온도', Colors.blue),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus(bool isConnected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        isConnected ? '프린터 연결됨' : '프린터 연결 안됨',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isConnected ? Colors.green : Colors.red,
        ),
      ),
    );
  }

  Widget _buildTemperatureInfo(String label, double temperature) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(
            '${temperature.toStringAsFixed(1)}°C',
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  LineChartBarData _createLineChartBarData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }
}
