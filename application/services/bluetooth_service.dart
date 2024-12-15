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
  final double nozzleTargetTemp;
  final double bedTargetTemp;

  TemperatureData({
    required this.time,
    required this.nozzleTemp,
    required this.bedTemp,
    required this.nozzleTargetTemp,
    required this.bedTargetTemp,
  });

  factory TemperatureData.fromJson(Map<String, dynamic> json) {
    final tool0 = json['tool0'] as Map<String, dynamic>;
    final bed = json['bed'] as Map<String, dynamic>;

    return TemperatureData(
      time: DateTime.now(),
      nozzleTemp: (tool0['actual'] as num).toDouble(),
      bedTemp: (bed['actual'] as num).toDouble(),
      nozzleTargetTemp: (tool0['target'] as num).toDouble(),
      bedTargetTemp: (bed['target'] as num).toDouble(),
    );
  }
}

class PrinterStatus {
  final double fanSpeed;
  final int timeLeft;
  final String? currentFile;
  final double progress;
  final int currentLayer;
  final int totalLayers;
  final double flowRate;

  PrinterStatus({
    required this.fanSpeed,
    required this.timeLeft,
    this.currentFile,
    required this.progress,
    required this.currentLayer,
    required this.totalLayers,
    required this.flowRate,
  });

  factory PrinterStatus.fromJson(Map<String, dynamic> json) {
    return PrinterStatus(
      fanSpeed: _parseDouble(json['fan_speed']) ?? 0.0,
      timeLeft: _parseInt(json['timeLeft']) ?? 0,
      currentFile: json['currentFile'] as String?,
      progress: _parseDouble(json['progress']) ?? 0.0,
      currentLayer: _parseInt(json['currentLayer']) ?? 0,
      totalLayers: _parseInt(json['totalLayers']) ?? 0,
      flowRate: _parseDouble(json['flow_rate']) ?? 100.0,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  factory PrinterStatus.empty() {
    return PrinterStatus(
      fanSpeed: 0,
      timeLeft: 0,
      currentFile: null,
      progress: 0,
      currentLayer: 0,
      totalLayers: 0,
      flowRate: 100.0,
    );
  }
}

class BluetoothService extends ChangeNotifier {
  static const double maxSafeTemperature = 260.0; // 안전 최대 온도 설정

  BluetoothConnection? _connection;
  String _connectionStatus = '연결 안됨';
  double? _currentNozzleTemperature;
  double? _currentBedTemperature;
  PrinterStatus _printerStatus = PrinterStatus.empty();
  Timer? _temperatureCheckTimer;
  Timer? _statusUpdateTimer;
  bool _notificationsEnabled = true;

  bool get notificationsEnabled => _notificationsEnabled;
  set notificationsEnabled(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  Future<void> showNotification(String title, String body) async {
    if (!_notificationsEnabled) return;

    // TODO: 알림 기능 구현
    print('Notification: $title - $body');
  }

  String get connectionStatus => _connectionStatus;
  double get currentNozzleTemperature => isConnected() ? _currentNozzleTemperature ?? 0 : 0;
  double get currentBedTemperature => isConnected() ? _currentBedTemperature ?? 0 : 0;
  double get currentTemperature => currentNozzleTemperature;
  PrinterStatus get printerStatus => _printerStatus;

  final List<TemperatureData> _temperatureHistory = [];
  final int _maxHistorySize = 3600; // 1시간 (3600초)

  List<TemperatureData> get temperatureHistory => List.unmodifiable(_temperatureHistory);

  static const chunkSize = 1024;
  static const maxRetries = 3;

  // 전역 스트림 컨트롤러 추가
  final StreamController<String> _responseController = StreamController<String>.broadcast();
  StreamSubscription? _inputSubscription;

  bool _isConnected = false;
  final _connectionController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;

  bool isConnected() => _connection != null && _connection!.isConnected;  // 연결 상태 확인

  bool _isPaused = false;
  bool get isPaused => _isPaused;

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
      _isConnected = true;
      _notifyConnectionChange(_isConnected);
      _startStatusUpdates(); // 연결 시 상태 업데이트 시작
      startPositionUpdates(); // 연결 시 위치 정보 업데이트 시작
      return _isConnected;
    } catch (e) {
      print('프린터 연결 실패: $e');
      _connectionStatus = '연결 실패';
      notifyListeners();
      _isConnected = false;
      _notifyConnectionChange(_isConnected);
      return false;
    }
  }

  void _startPeriodicTemperatureCheck() {
    _temperatureCheckTimer?.cancel();
    _temperatureCheckTimer = Timer.periodic(Duration(seconds: 5), (_) {
      final command = '${json.encode({
        'type': 'GET_STATUS'
      })}\n';
      sendCommand(command);
    });
  }

  Future<void> sendGCode(String gcode) async {
    if (!isConnected()) {
      throw Exception('블루투스가 연결되지 않았습니다');
    }

    try {
      // G-code 명령어를 전송
      final commandWithNewline = gcode.endsWith('\n') ? gcode : '$gcode\n';
      _connection!.output.add(Uint8List.fromList(utf8.encode(commandWithNewline)));
      await _connection!.output.allSent;
      print('G-code 전송: $gcode');
    } catch (e) {
      print('G-code 전송 실패: $e');
      throw Exception('G-code 전송 실패: $e');
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
        throw Exception("파 전송 실패");
      }

      print('G-code 파일 전송 완료: $fileName');
    } catch (e) {
      print('G-code 파일 전송 실패: $e');
      throw Exception("G-code 파일 전송 실패: $e");
    }
  }

  void _handlePrinterResponse(Uint8List data) {
    try {
      String responseStr = String.fromCharCodes(data);
      List<String> responses = responseStr.split('\n');

      for (String response in responses) {
        if (response.trim().isEmpty) continue;

        try {
          _responseController.add(response.trim());
          Map<String, dynamic> jsonResponse = json.decode(response.trim());

          // "status"가 "ok"인지 확인
          if (jsonResponse['status'] == 'ok') {
            final statusData = jsonResponse['data'];

            // 온도 데이터 파싱
            if (statusData['temperature'] != null) {
              final tool0 = statusData['temperature']['tool0'];
              final bed = statusData['temperature']['bed'];

              _currentNozzleTemperature = tool0['actual']?.toDouble();
              _currentBedTemperature = bed['actual']?.toDouble();

              _temperatureHistory.add(TemperatureData(
                time: DateTime.now(),
                nozzleTemp: _currentNozzleTemperature!,
                bedTemp: _currentBedTemperature!,
                nozzleTargetTemp: tool0['target']?.toDouble() ?? 0.0,
                bedTargetTemp: bed['target']?.toDouble() ?? 0.0,
              ));

              if (_temperatureHistory.length > _maxHistorySize) {
                _temperatureHistory.removeAt(0);
              }
            }

            // 프린터 상태 데이터 파싱
            _printerStatus = PrinterStatus.fromJson(statusData);
            notifyListeners();
          }
        } catch (e) {
          print('응답 처리 중 오류: $e');
        }
      }
    } catch (e) {
      print('응답 데이터 처리 중 오류: $e');
    }
  }

  void _updateTemperatureHistory() {
    final now = DateTime.now();
    final newData = TemperatureData(
      time: now,
      nozzleTemp: currentNozzleTemperature,
      bedTemp: currentBedTemperature,
      nozzleTargetTemp: 0.0, // 또는 실제 목표 온도
      bedTargetTemp: 0.0, // 또는 실제 목표 온도
    );
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
    _connectionStatus = '연 안';
    notifyListeners();
  }

  @override
  void dispose() {
    _temperatureCheckTimer?.cancel();
    _inputSubscription?.cancel();
    _responseController.close();
    disconnect(); // _device?.disconnect() 대신 disconnect() 메서드 호출
    _statusUpdateTimer?.cancel();
    _connectionController.close();
    stopPositionUpdates(); // 위치 정보 업데이트 중지
    super.dispose();
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
      // 먼저 파일 내용을 읽어옴
      final FileService fileService = getFileService();
      final String content = await fileService.readGCodeFile(fileName);
      final List<int> fileBytes = utf8.encode(content);

      // 파일 전송 작 알림
      final startCommand = '${json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'start',
        'filename': fileName,
        'total_size': fileBytes.length
      })}\n';

      final startResponse = await _sendCommandAndWaitResponse(startCommand);
      final startJson = json.decode(startResponse);

      // 파일이 이미 존재하는 우
      if (startJson['message'] == "File already exists") {
        print('File already exists, skipping upload');
        onProgress(1.0); // 진행률 100%로 설정
        return true;
      }

      // 청크 단위로 파일 전송
      for (var i = 0; i < fileBytes.length; i += chunkSize) {
        final end = min(i + chunkSize, fileBytes.length);
        final chunk = fileBytes.sublist(i, end);

        final chunkCommand = json.encode({
          'type': 'UPLOAD_GCODE',
          'action': 'chunk',
          'data': base64Encode(chunk),
          'chunk_index': i ~/ chunkSize,
          'total_chunks': (fileBytes.length / chunkSize).ceil(),
          'is_last': end == fileBytes.length
        });

        await sendGCode(chunkCommand);
        onProgress((i + chunkSize) / fileBytes.length);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 파일 전송 완료 알림
      final finishCommand = '${json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'finish',
        'filename': fileName
      })}\n';

      await sendGCode(finishCommand);
      return true;
    } catch (e) {
      onError(e.toString());
      final abortCommand = '${json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'abort',
        'filename': fileName
      })}\n';

      await sendGCode(abortCommand);
      return false;
    }
  }

  // 명령어를 보내고 응답을 기다리는 메서드 수정
  Future<String> _sendCommandAndWaitResponse(String command) async {
    if (!isConnected()) {
      throw Exception('블루투스가 연결되지 않았습니다');
    }

    final completer = Completer<String>();
    StreamSubscription? responseSubscription;

    try {
      // 응답 리스너 설정
      responseSubscription = _responseController.stream.listen((response) {
        try {
          // JSON 파싱 시도
          json.decode(response); // jsonResponse를 사용하지 않고 단순히 파싱만 수행
          if (!completer.isCompleted) {
            completer.complete(response);
          }
        } catch (e) {
          // JSON이 아닌 응답은 무시
          print('Invalid JSON response: $response');
        }
      });

      // 명령어 전송
      await sendCommand(command);

      // 타임아웃 시간을 10초로 증가
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('응답 시간 초과'),
      );
    } finally {
      await responseSubscription?.cancel();
    }
  }

  Future<void> uploadGCodeFile(
      String filename,
      List<int> fileContent,
      {Function(bool)? onCancel,
        Function(double)? onProgress}
      ) async {
    if (!isConnected()) {
      throw Exception('블루투스가 연결되지 않았습니다');
    }

    const int chunkSize = 1024;  // 청크 크기를 1KB로 감소
    try {
      // 파일 전송 시작 알림
      final startCommand = jsonEncode({
        'type': 'UPLOAD_GCODE',
        'action': 'start',
        'filename': filename,
        'total_size': fileContent.length
      });

      final startResponse = await _sendCommandAndWaitResponse(startCommand);
      final startJson = jsonDecode(startResponse);

      // 파일이 이미 존재하는 경우
      if (startJson['message'] == "File already exists") {
        print('File already exists, skipping upload');
        onProgress?.call(1.0); // 진행률 100%로 설정
        return;
      }

      print('Total file size: ${fileContent.length}');

      double lastProgress = 0.0;
      int totalSent = 0;

      for (var i = 0; i < fileContent.length; i += chunkSize) {
        if (onCancel?.call(true) == true) {
          await sendCommand(jsonEncode({
            'type': 'UPLOAD_GCODE',
            'action': 'abort',
            'filename': filename
          }));
          return;
        }

        final end = min(i + chunkSize, fileContent.length);
        final chunk = fileContent.sublist(i, end);

        // base64 인코딩 시 URL 안전 문자만 사용
        String base64Data = base64Url.encode(chunk)
            .replaceAll('+', '-')
            .replaceAll('/', '_')
            .replaceAll('=', '');  // 패딩 제거

        // 청크 데이터를 한 번에 전송
        final command = jsonEncode({
          'type': 'UPLOAD_GCODE',
          'action': 'chunk',
          'data': base64Data,
          'chunk_index': i ~/ chunkSize,
          'total_chunks': (fileContent.length / chunkSize).ceil(),
          'is_last': end == fileContent.length
        });

        await sendCommand(command);
        await Future.delayed(const Duration(milliseconds: 10));

        totalSent += chunk.length;
        final currentProgress = totalSent / fileContent.length;

        if (currentProgress - lastProgress >= 0.01) {
          onProgress?.call(currentProgress);
          lastProgress = currentProgress;
        }
      }

      await sendCommand(jsonEncode({
        'type': 'UPLOAD_GCODE',
        'action': 'finish',
        'filename': filename
      }));

      onProgress?.call(1.0);
      print('Upload completed');
    } catch (e) {
      print('파일 업로드 실패: $e');
      try {
        await sendCommand(jsonEncode({
          'type': 'UPLOAD_GCODE',
          'action': 'abort',
          'filename': filename
        }));
      } catch (_) {}
      throw Exception('G-code 파일 업로드 실패: $e');
    }
  }

  Future<void> startPrint(String fileName) async {
    if (!isConnected()) {
      throw Exception("프린터가 연결되어 있지 않습니다");
    }

    try {
      await sendGCode(jsonEncode({
        'type': 'START_PRINT',
        'filename': fileName
      }));
      print('출력 시작 명령 전송됨: $fileName');
    } catch (e) {
      print('출력 시작 실패: $e');
      throw Exception("출력 시작 실패: $e");
    }
  }

  Future<void> sendCommand(String command) async {
    if (!isConnected()) {
      throw Exception('블루투스가 연결되지 않��습니다');
    }

    try {
      final commandWithNewline = command.endsWith('\n') ? command : '$command\n';
      _connection!.output.add(Uint8List.fromList(utf8.encode(commandWithNewline)));
      await _connection!.output.allSent;
      print('명령어 전송: $command');
    } catch (e) {
      print('명령어 전송 실패: $e');
      throw Exception('명령어 전송 실패: $e');
    }
  }

  Future<void> pausePrint() async {
    if (!isConnected()) {
      throw Exception("프린터가 연결되어 있지 않습니다");
    }

    try {
      await sendCommand(jsonEncode({
        'type': 'PAUSE'
      }));
      _isPaused = true;
      notifyListeners();
      print('일시정지 명령 전송됨');
    } catch (e) {
      print('일시정지 실패: $e');
      throw Exception("일시정지 실패: $e");
    }
  }

  Future<void> resumePrint() async {
    if (!isConnected()) {
      throw Exception("프린터가 연결되어 있지 않습니다");
    }

    try {
      await sendCommand(jsonEncode({
        'type': 'RESUME'
      }));
      _isPaused = false;
      notifyListeners();
      print('재개 명령 전송됨');
    } catch (e) {
      print('재개 실패: $e');
      throw Exception("재개 실패: $e");
    }
  }

  Future<void> cancelPrint() async {
    if (!isConnected()) {
      throw Exception("프린터가 연결되어 있지 않습니다");
    }

    try {
      await sendCommand(jsonEncode({
        'type': 'CANCEL'
      }));
      print('취소 명령 전송됨');
    } catch (e) {
      print('취소 실패: $e');
      throw Exception("취소 실패: $e");
    }
  }

  // 프린터 상태 주기적 업데이트
  void _startStatusUpdates() {
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isConnected()) {  // isConnected() 메서드 사용
        _updatePrinterStatus();
      }
    });
  }

  Future<void> _updatePrinterStatus() async {
    try {
      final command = jsonEncode({
        'type': 'GET_STATUS'
      });

      // 명령을 보내고 응답을 기다림
      final response = await _sendCommandAndWaitResponse(command);
      final responseData = jsonDecode(response);

      if (responseData['success'] == true && responseData['data'] != null) {
        // 새로운 프린터 상태 객체 생성
        _printerStatus = PrinterStatus.fromJson(responseData['data']);
        notifyListeners();
      }
    } catch (e) {
      print('프린터 상태 업데이트 실패: $e');
    }
  }

  void _notifyConnectionChange(bool isConnected) {
    _connectionController.add(isConnected);
    notifyListeners();
  }

  Map<String, double>? _currentPosition;
  Map<String, double>? get currentPosition => _currentPosition;

  Future<Map<String, double>?> getPosition() async {
    try {
      final response = await _sendCommandAndWaitResponse(
          jsonEncode({
            'type': 'GET_POSITION',
          })
      );

      final responseData = jsonDecode(response);
      if (responseData['success'] == true && responseData['data'] != null) {
        _currentPosition = Map<String, double>.from(responseData['data']);
        notifyListeners();
        return _currentPosition;
      }
      return null;
    } catch (e) {
      print('위치 정보 가져오기 실패: $e');
      return null;
    }
  }

  // 주기적으로 위치 정보 업데이트
  Timer? _positionUpdateTimer;

  void startPositionUpdates() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isConnected) {
        getPosition();
      }
    });
  }

  void stopPositionUpdates() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
  }

  Future<void> setNozzleTemperature(double temperature) async {
    if (_connection == null) return;
    try {
      final command = {
        'type': 'SET_TEMP',
        'target': 'nozzle',
        'temperature': temperature,
      };
      await _sendCommand(command);
      notifyListeners();
    } catch (e) {
      print('Failed to set nozzle temperature: $e');
      rethrow;
    }
  }

  Future<void> setBedTemperature(double temperature) async {
    if (_connection == null) return;
    try {
      final command = {
        'type': 'SET_TEMP',
        'target': 'bed',
        'temperature': temperature,
      };
      await _sendCommand(command);
      notifyListeners();
    } catch (e) {
      print('Failed to set bed temperature: $e');
      rethrow;
    }
  }

  Future<void> setFanSpeed(double speed) async {
    if (_connection == null) return;
    try {
      // Ensure speed is between 0 and 100
      speed = speed.clamp(0, 100);
      final command = {
        'type': 'SET_FAN_SPEED',
        'speed': speed,
      };
      await _sendCommand(command);
      notifyListeners();
    } catch (e) {
      print('Failed to set fan speed: $e');
      rethrow;
    }
  }

  Future<void> setFlowRate(double rate) async {
    if (_connection == null) return;
    try {
      // Ensure rate is between 75 and 125
      rate = rate.clamp(75, 125);
      final command = {
        'type': 'SET_FLOW_RATE',
        'rate': rate,
      };
      await _sendCommand(command);
      notifyListeners();
    } catch (e) {
      print('Failed to set flow rate: $e');
      rethrow;
    }
  }

  Future<void> extrude(double amount) async {
    if (_connection == null) return;
    try {
      // Ensure amount is between 0 and 100
      amount = amount.clamp(0, 100);
      final command = {
        'type': 'EXTRUDE',
        'amount': amount,
      };
      await _sendCommand(command);
      notifyListeners();
    } catch (e) {
      print('Failed to extrude: $e');
      rethrow;
    }
  }

  Future<void> retract(double amount) async {
    if (_connection == null) return;
    try {
      // Ensure amount is between 0 and 100
      amount = amount.clamp(0, 100);
      final command = {
        'type': 'RETRACT',
        'amount': amount,
      };
      await _sendCommand(command);
      notifyListeners();
    } catch (e) {
      print('Failed to retract: $e');
      rethrow;
    }
  }

  Future<void> _sendCommand(Map<String, dynamic> command) async {
    if (_connection == null) return;
    try {
      final jsonStr = json.encode(command);
      final data = Uint8List.fromList(utf8.encode(jsonStr));
      _connection!.output.add(data);
      await _connection!.output.allSent;
    } catch (e) {
      print('Failed to send command: $e');
      rethrow;
    }
  }

  bool get isPrinting {
    return _printerStatus.currentFile != null && 
           _printerStatus.progress > 0 && 
           !_isPaused;
  }

  // 제어 가능 여부 체크
  bool canControl() {
    // 프린터가 연결되어 있고,
    // 출력 중이 아니거나 (일시정지 상태일 때는 제어 가능)
    return isConnected() && 
           (!isPrinting || _isPaused);  // 수정된 부분
  }
}