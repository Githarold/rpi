import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../services/file_service.dart';
import 'dart:convert';
import 'dart:math';

class TemperatureData {
  final DateTime time;
  final double nozzleTemp;
  final double bedTemp;

  TemperatureData(this.time, this.nozzleTemp, this.bedTemp);
}

class BluetoothService extends ChangeNotifier {
  static const double maxSafeTemperature = 260.0; // 안전 최대 온도 설정

  BluetoothConnection? _connection;
  String _connectionStatus = '연결 안됨';
  double? _currentNozzleTemperature;
  double? _currentBedTemperature;
  final String _printerStatus = '대기 중';
  Timer? _temperatureCheckTimer;

  String get connectionStatus => _connectionStatus;
  double get currentNozzleTemperature => isConnected() ? _currentNozzleTemperature ?? 0 : 0;
  double get currentBedTemperature => isConnected() ? _currentBedTemperature ?? 0 : 0;
  double get currentTemperature => currentNozzleTemperature;
  String get printerStatus => _printerStatus;

  final List<TemperatureData> _temperatureHistory = [];
  final int _maxHistorySize = 3600; // 1시간 (3600초)

  List<TemperatureData> get temperatureHistory => List.unmodifiable(_temperatureHistory);

  static const chunkSize = 1024;
  static const maxRetries = 3;

  Future<bool> connectToPrinter(String address) async {
    try {
      print('프린터 연결 시도: $address');
      _connection = await BluetoothConnection.toAddress(address).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('연결 시간 초과'),
      );
      print('블루투스 연결 성공');
      _connectionStatus = '연결됨';

      _connection!.input!.listen(_handlePrinterResponse);
      _startPeriodicTemperatureCheck();
      notifyListeners();
      return true;
    } catch (e) {
      print('프린터 연결 실패: $e');
      _connectionStatus = '연결 실패';
      notifyListeners();
      return false;
    }
  }

  void _startPeriodicTemperatureCheck() {
    _temperatureCheckTimer?.cancel();
    _temperatureCheckTimer = Timer.periodic(Duration(seconds: 5), (_) {
        final command = json.encode({
            'type': 'GET_STATUS'
        }) + '\n';
        sendCommand(command);
    });
  }

  Future<void> sendGCode(String gcode) async {
    if (_connection == null || _connection!.isConnected == false) {
      throw Exception("프린터가 연결되어 있지 않습니다");
    }
    try {
      _connection!.output.add(Uint8List.fromList(gcode.codeUnits));
      await _connection!.output.allSent;
      print('G-code 전송됨: $gcode');
    } catch (e) {
      print('G-code 전송 실패: $e');
      throw Exception("G-code 전송 실패: $e");
    }
  }

  Future<void> sendGCodeFile(
    String fileName, 
    [BuildContext? context, 
    Function(double)? onProgress]
  ) async {
    if (!isConnected()) {
      throw Exception("프린터가 연결되어 있지 않습니다");
    }

    try {
      // transferGCodeFile 메서드 호출
      bool success = await transferGCodeFile(
        fileName,
        onProgress: (progress) {
          // 진행률 처리
          onProgress?.call(progress); // 진행률 콜백 호출
          print('전송 진행률: ${(progress * 100).toStringAsFixed(1)}%');
        },
        onError: (error) {
          print('전송 오류: $error');
          if (context != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('전송 오류: $error')),
            );
          }
        },
      );

      if (!success) {
        throw Exception("파일 전송 실패");
      }

      print('G-code 파일 전송 완료: $fileName');
    } catch (e) {
      print('G-code 파일 전송 실패: $e');
      throw Exception("G-code 파일 전송 실패: $e");
    }
  }

  void _handlePrinterResponse(Uint8List data) {
    try {
        String response = String.fromCharCodes(data);
        Map<String, dynamic> jsonResponse = json.decode(response);
        
        if (jsonResponse['status'] == 'ok' && jsonResponse['data'] != null) {
            final statusData = jsonResponse['data'];
            _currentNozzleTemperature = statusData['temperatures']['nozzle'].toDouble();
            _currentBedTemperature = statusData['temperatures']['bed'].toDouble();
            notifyListeners();
        }
    } catch (e) {
        print('응답 처리 오류: $e');
    }
  }

  void _updateTemperatureHistory() {
    final now = DateTime.now();
    final newData = TemperatureData(now, currentNozzleTemperature, currentBedTemperature);
    _temperatureHistory.add(newData);

    _temperatureHistory.removeWhere((data) => now.difference(data.time).inSeconds > _maxHistorySize);
  }

  @override
  void notifyListeners() {
    _updateTemperatureHistory();
    super.notifyListeners();
  }

  Future<void> disconnect() async {
    await _connection?.close();
    _connection = null;
    _connectionStatus = '연결 안됨';
    notifyListeners();
  }

  @override
  void dispose() {
    _temperatureCheckTimer?.cancel();
    disconnect(); // _device?.disconnect() 대신 disconnect() 메서드 호출
    super.dispose();
  }

  bool isConnected() {
    return _connection != null && _connection!.isConnected;
  }

  // 호환성을 위해 updateTemperatures 메서드 추가
  void updateTemperatures(double nozzle, double bed) {
    _currentNozzleTemperature = nozzle;
    _currentBedTemperature = bed;
    notifyListeners();
  }

  Future<double> getTemperature(String type) async {
    if (!isConnected()) return 0;

    if (type == 'nozzle') {
      return _currentNozzleTemperature ?? 0;
    } else if (type == 'bed') {
      return _currentBedTemperature ?? 0;
    } else {
      throw ArgumentError('잘못된 온도 유형');
    }
  }

  Future<bool> transferGCodeFile(String fileName, {
    required Function(double) onProgress,
    required Function(String) onError,
  }) async {
    if (!isConnected()) {
      onError("프린터가 연결되어 있지 않습니다");
      return false;
    }

    try {
      final FileService fileService = getFileService();
      final String content = await fileService.readGCodeFile(fileName);
      final List<int> fileBytes = utf8.encode(content);
      
      // 파일 전송 시작 알림
      final startCommand = json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'start',
        'filename': fileName,
        'total_size': fileBytes.length
      }) + '\n';  // 개행 문자 추가
      
      await sendGCode(startCommand);

      // 청크 단위로 파일 전송
      for (var i = 0; i < fileBytes.length; i += chunkSize) {
        final end = min(i + chunkSize, fileBytes.length);
        final chunk = fileBytes.sublist(i, end);
        
        final chunkCommand = json.encode({
          'type': 'UPLOAD_GCODE',
          'action': 'chunk',
          'data': base64Encode(chunk)
        }) + '\n';  // 개행 문자 추가
        
        await sendGCode(chunkCommand);

        onProgress((i + chunkSize) / fileBytes.length);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 파일 전송 완료 알림
      final finishCommand = json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'finish',
        'filename': fileName
      }) + '\n';  // 개행 문자 추가
      
      await sendGCode(finishCommand);

      return true;
    } catch (e) {
      onError(e.toString());
      final abortCommand = json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'abort',
        'filename': fileName
      }) + '\n';  // 개행 문자 추가
      
      await sendGCode(abortCommand);
      return false;
    }
  }

  Future<void> startPrint(String fileName) async {
    if (!isConnected()) {
      throw Exception("프린터가 연결되어 있지 않습니다");
    }

    try {
      await sendGCode(json.encode({
        'type': 'START_PRINT',
        'filename': fileName
      }));
      
      print('출력 시작 명령 전송됨: $fileName');
    } catch (e) {
      print('출력 시작 실패: $e');
      throw Exception("출력 시작 실패: $e");
    }
  }
}
