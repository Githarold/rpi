import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import '../theme/theme_provider.dart';
import '../services/bluetooth_service.dart';
import 'info_screen.dart';
import 'license_screen.dart';
import 'dart:convert';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  String _temperatureUnit = '섭씨';
  double _nozzleTemperature = 200.0;
  double _bedTemperature = 60.0;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _getAppVersion();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      
      final bluetoothService = context.read<BluetoothService>();
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
        _temperatureUnit = prefs.getString('temperature_unit') ?? '섭씨';
        _nozzleTemperature = prefs.getDouble('nozzle_temperature') ?? 200.0;
        _bedTemperature = prefs.getDouble('bed_temperature') ?? 60.0;
      });
      bluetoothService.notificationsEnabled = _notificationsEnabled;
    } catch (e) {
      print('Error loading settings: $e');
      // 기본값 설정
      _notificationsEnabled = true;
      _temperatureUnit = '섭씨';
      _nozzleTemperature = 200.0;
      _bedTemperature = 60.0;
    }
  }

  Future<void> _getAppVersion() async {
    try {
      final yamlString = await rootBundle.loadString('pubspec.yaml');
      if (!mounted) return;
      
      final yamlMap = loadYaml(yamlString);
      final version = yamlMap['version'];
      setState(() {
        _appVersion = version ?? '버전 정보를 찾을 수 없습니다';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _appVersion = '버전 정보를 가져올 수 없습니다';
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!mounted) return;
    
    final bluetoothService = context.read<BluetoothService>();
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool('notifications_enabled', _notificationsEnabled);
    await prefs.setString('temperature_unit', _temperatureUnit);
    await prefs.setDouble('nozzle_temperature', _nozzleTemperature);
    await prefs.setDouble('bed_temperature', _bedTemperature);
    
    if (!mounted) return;
    bluetoothService.notificationsEnabled = _notificationsEnabled;
  }

  bool _canControl(BluetoothService bluetoothService) {
    return bluetoothService.canControl();  // 새로운 메서드 사용
  }

  void _showTemperatureDialog(String target, double currentTemp, Function(double) onSave) {
    final bluetoothService = context.read<BluetoothService>();
    if (!_canControl(bluetoothService)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프린터가 연결되어 있고 출력 중이 아닐 때만 제어할 수 있습니다')),
      );
      return;
    }

    double tempValue = currentTemp;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$target 온도 설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '온도',
                suffixText: _temperatureUnit == '섭씨' ? '°C' : '°F',
              ),
              controller: TextEditingController(text: currentTemp.toString()),
              onChanged: (value) {
                tempValue = double.tryParse(value) ?? currentTemp;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _setTemperature(target, tempValue, onSave, scaffoldMessenger, bluetoothService);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Future<void> _setTemperature(String target, double tempValue, Function(double) onSave, 
      ScaffoldMessengerState messenger, BluetoothService bluetoothService) async {
    try {
      if (target == '노즐') {
        await bluetoothService.setNozzleTemperature(tempValue);
      } else {
        await bluetoothService.setBedTemperature(tempValue);
      }
      onSave(tempValue);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('온도 설정 실패: $e')),
      );
    }
  }

  void _showFlowRateDialog() {
    double rate = 100;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final bluetoothService = context.read<BluetoothService>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('필라멘트 압출 속도'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '속도',
                suffixText: '%',
                helperText: '75-125% 사이의 값을 입력하세요',
              ),
              controller: TextEditingController(text: '100'),
              onChanged: (value) {
                rate = double.tryParse(value) ?? 100;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              if (rate < 75 || rate > 125) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('속도는 75-125% 사이여야 합니다')),
                );
                return;
              }
              Navigator.pop(dialogContext);
              _setFlowRate(rate, scaffoldMessenger, bluetoothService);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Future<void> _setFlowRate(double rate, ScaffoldMessengerState messenger, 
      BluetoothService bluetoothService) async {
    try {
      await bluetoothService.setFlowRate(rate);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('압출 속도 설정 실패: $e')),
      );
    }
  }

  void _showExtrudeDialog(bool isRetract) {
    double amount = 5;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final bluetoothService = context.read<BluetoothService>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isRetract ? '필라멘트 후퇴' : '필라멘트 압출'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '길이',
                suffixText: 'mm',
                helperText: '0-100mm 사이의 값을 입력하세요',
              ),
              controller: TextEditingController(text: '5'),
              onChanged: (value) {
                amount = double.tryParse(value) ?? 5;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              if (amount <= 0 || amount > 100) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('길이는 0-100mm 사이여야 합니다')),
                );
                return;
              }
              Navigator.pop(dialogContext);
              _setExtrusion(amount, isRetract, scaffoldMessenger, bluetoothService);
            },
            child: const Text('실행'),
          ),
        ],
      ),
    );
  }

  Future<void> _setExtrusion(double amount, bool isRetract, ScaffoldMessengerState messenger, 
      BluetoothService bluetoothService) async {
    try {
      if (isRetract) {
        await bluetoothService.retract(amount);
      } else {
        await bluetoothService.extrude(amount);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${isRetract ? "후퇴" : "압출"} 실패: $e')),
      );
    }
  }

  void _moveAxis(String axis, double distance) {
    final bluetoothService = context.read<BluetoothService>();
    if (!_canControl(bluetoothService)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프린터가 연결되어 있고 출력 중이 아닐 때만 제어할 수 있습니다')),
      );
      return;
    }

    bluetoothService.sendCommand(
      jsonEncode({
        'type': 'MOVE_AXIS',
        'axis': axis,
        'distance': distance,
      })
    );
  }

  Widget _buildAxisControl(String label, String axis) {
    return Column(
      children: [
        Text(label),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _moveAxis(axis, -1),
              icon: const Icon(Icons.remove),
            ),
            IconButton(
              onPressed: () => _moveAxis(axis, 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAxisControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('축 제어', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAxisControl('X축', 'x'),
                _buildAxisControl('Y축', 'y'),
                _buildAxisControl('Z축', 'z'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFan(bool value, BluetoothService bluetoothService) async {
    if (!_canControl(bluetoothService)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프린터가 연결되어 있고 출력 중이 아닐 때만 제어할 수 있습니다')),
      );
      return;
    }

    try {
      await bluetoothService.setFanSpeed(value ? 100.0 : 0.0);
      // 상태 업데이트 제거 - 응답에서 처리
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('팬 제어 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothService = context.watch<BluetoothService>();
    final currentNozzleTemp = bluetoothService.currentNozzleTemperature;
    final currentBedTemp = bluetoothService.currentBedTemperature;
    final themeProvider = context.watch<ThemeProvider>();
    final canControl = _canControl(bluetoothService);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('알림'),
            trailing: Switch(
              value: _notificationsEnabled,
              onChanged: (bool value) {
                setState(() {
                  _notificationsEnabled = value;
                });
                _saveSettings();
              },
            ),
          ),
          ListTile(
            title: const Text('온도 단위'),
            subtitle: Text(_temperatureUnit),
            onTap: () {
              setState(() {
                _temperatureUnit = _temperatureUnit == '섭씨' ? '화씨' : '섭씨';
              });
              _saveSettings();
            },
          ),
          ListTile(
            title: const Text('노즐 온도'),
            subtitle: Text('현재: ${currentNozzleTemp.toStringAsFixed(1)}°${_temperatureUnit == '섭씨' ? 'C' : 'F'} / 목표: ${_nozzleTemperature.toStringAsFixed(1)}°${_temperatureUnit == '섭씨' ? 'C' : 'F'}'),
            enabled: canControl,
            onTap: () {
              _showTemperatureDialog(
                '노즐',
                _nozzleTemperature,
                (value) {
                  setState(() {
                    _nozzleTemperature = value;
                  });
                  _saveSettings();
                },
              );
            },
          ),
          ListTile(
            title: const Text('베드 온도'),
            subtitle: Text('현재: ${currentBedTemp.toStringAsFixed(1)}°${_temperatureUnit == '섭씨' ? 'C' : 'F'} / 목표: ${_bedTemperature.toStringAsFixed(1)}°${_temperatureUnit == '섭씨' ? 'C' : 'F'}'),
            enabled: canControl,
            onTap: () {
              _showTemperatureDialog(
                '베드',
                _bedTemperature,
                (value) {
                  setState(() {
                    _bedTemperature = value;
                  });
                  _saveSettings();
                },
              );
            },
          ),
          ListTile(
            title: const Text('팬'),
            subtitle: Text(bluetoothService.isFanOn ? "켜짐" : "꺼짐"),
            enabled: canControl,
            trailing: Switch(
              value: bluetoothService.isFanOn,
              onChanged: canControl ? (value) => _toggleFan(value, bluetoothService) : null,
            ),
          ),
          ListTile(
            title: const Text('필라멘트 압출 속도'),
            subtitle: Text('현재: ${bluetoothService.printerStatus.flowRate.toStringAsFixed(1)}%'),
            enabled: canControl,
            onTap: canControl ? _showFlowRateDialog : null,
          ),
          Opacity(
            opacity: canControl ? 1.0 : 0.5,
            child: Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: const Text('압출'),
                    trailing: const Icon(Icons.arrow_downward),
                    enabled: canControl,
                    onTap: canControl ? () => _showExtrudeDialog(false) : null,
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: const Text('후퇴'),
                    trailing: const Icon(Icons.arrow_upward),
                    enabled: canControl,
                    onTap: canControl ? () => _showExtrudeDialog(true) : null,
                  ),
                ),
              ],
            ),
          ),
          Opacity(
            opacity: canControl ? 1.0 : 0.5,
            child: _buildAxisControls(),
          ),
          ListTile(
            title: const Text('다크 모드'),
            subtitle: const Text('어두운 테마 사용'),
            trailing: Switch(
              value: themeProvider.isDarkMode,
              onChanged: (bool value) {
                themeProvider.toggleTheme();
              },
            ),
          ),
          ListTile(
            title: const Text('앱 버전'),
            subtitle: Text(_appVersion),
            trailing: const Icon(Icons.info_outline),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InfoScreen()),
              );
            },
          ),
          ListTile(
            title: const Text('오픈소스 라이선스'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LicenseScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
