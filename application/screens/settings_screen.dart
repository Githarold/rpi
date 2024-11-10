import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import '../theme/theme_provider.dart';
import 'info_screen.dart';
import 'license_screen.dart';

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
    _loadSettings().then((_) {
      _getAppVersion();
    });
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
        _temperatureUnit = prefs.getString('temperature_unit') ?? '섭씨';
        _nozzleTemperature = prefs.getDouble('nozzle_temperature') ?? 200.0;
        _bedTemperature = prefs.getDouble('bed_temperature') ?? 60.0;
      });
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
      final yamlMap = loadYaml(yamlString);
      final version = yamlMap['version'];
      setState(() {
        _appVersion = version ?? '버전 정보를 찾을 수 없습니다';
      });
    } catch (e) {
      setState(() {
        _appVersion = '버전 정보를 가져올 수 없습니다';
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', _notificationsEnabled);
    await prefs.setString('temperature_unit', _temperatureUnit);
    await prefs.setDouble('nozzle_temperature', _nozzleTemperature);
    await prefs.setDouble('bed_temperature', _bedTemperature);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('프린터 설정'),
          ListTile(
            title: const Text('기본 노즐 온도'),
            subtitle: Text('${_nozzleTemperature.toStringAsFixed(1)}°${_temperatureUnit == '섭씨' ? 'C' : 'F'}'),
            trailing: const Icon(Icons.edit),
            onTap: () => _showTemperatureDialog('노즐', _nozzleTemperature, (value) {
              setState(() => _nozzleTemperature = value);
              _saveSettings();
            }),
          ),
          ListTile(
            title: const Text('기본 베드 온도'),
            subtitle: Text('${_bedTemperature.toStringAsFixed(1)}°${_temperatureUnit == '섭씨' ? 'C' : 'F'}'),
            trailing: const Icon(Icons.edit),
            onTap: () => _showTemperatureDialog('베드', _bedTemperature, (value) {
              setState(() => _bedTemperature = value);
              _saveSettings();
            }),
          ),
          ListTile(
            title: const Text('온도 단위'),
            subtitle: Text(_temperatureUnit),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _showTemperatureUnitDialog,
          ),
          _buildSectionHeader('앱 설정'),
          SwitchListTile(
            title: const Text('알림'),
            subtitle: const Text('프린트 완료 및 오류 알림'),
            value: _notificationsEnabled,
            onChanged: (bool value) {
              setState(() => _notificationsEnabled = value);
              _saveSettings();
            },
            secondary: const Icon(Icons.notifications),
          ),
          SwitchListTile(
            title: const Text('다크 모드'),
            subtitle: const Text('어두운 테마 사용'),
            value: themeProvider.isDarkMode,
            onChanged: (bool value) {
              themeProvider.toggleTheme();
            },
            secondary: const Icon(Icons.dark_mode),
          ),
          _buildSectionHeader('정보'),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.grey[700],
        ),
      ),
    );
  }

  void _showTemperatureUnitDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('온도 단위 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile(
                title: const Text('섭씨 (°C)'),
                value: '섭씨',
                groupValue: _temperatureUnit,
                onChanged: (value) {
                  setState(() {
                    _temperatureUnit = value.toString();
                    _convertTemperatures(toCelsius: true);
                  });
                  _saveSettings();
                  Navigator.of(context).pop();
                },
              ),
              RadioListTile(
                title: const Text('화씨 (°F)'),
                value: '화씨',
                groupValue: _temperatureUnit,
                onChanged: (value) {
                  setState(() {
                    _temperatureUnit = value.toString();
                    _convertTemperatures(toCelsius: false);
                  });
                  _saveSettings();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _convertTemperatures({required bool toCelsius}) {
    if (toCelsius) {
      _nozzleTemperature = (_nozzleTemperature - 32) * 5 / 9;
      _bedTemperature = (_bedTemperature - 32) * 5 / 9;
    } else {
      _nozzleTemperature = (_nozzleTemperature * 9 / 5) + 32;
      _bedTemperature = (_bedTemperature * 9 / 5) + 32;
    }
  }

  void _showTemperatureDialog(String type, double currentTemp, Function(double) onChanged) {
    TextEditingController textController = TextEditingController(text: currentTemp.toStringAsFixed(1));
    double tempValue = currentTemp;

    double minTemp = _temperatureUnit == '섭씨' ? 0 : 32;
    double maxTemp = _temperatureUnit == '섭씨' ? 300 : 572;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('$type 온도 설정'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: tempValue.clamp(minTemp, maxTemp),
                    min: minTemp,
                    max: maxTemp,
                    divisions: 300,
                    label: tempValue.round().toString(),
                    onChanged: (double value) {
                      setState(() {
                        tempValue = value;
                        textController.text = value.toStringAsFixed(1);
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      suffixText: _temperatureUnit == '섭씨' ? '°C' : '°F',
                      border: OutlineInputBorder(),
                      labelText: '$type 온도',
                    ),
                    onChanged: (value) {
                      double? newTemp = double.tryParse(value);
                      if (newTemp != null) {
                        setState(() {
                          tempValue = newTemp.clamp(minTemp, maxTemp);
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('취소'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('확인'),
                  onPressed: () {
                    double finalTemp = tempValue.clamp(minTemp, maxTemp);
                    onChanged(finalTemp);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}
