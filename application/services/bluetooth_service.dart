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

  PrinterStatus({
    required this.fanSpeed,
    required this.timeLeft,
    this.currentFile,
    required this.progress,
    required this.currentLayer,
    required this.totalLayers,
  });

  factory PrinterStatus.fromJson(Map<String, dynamic> json) {
    return PrinterStatus(
      fanSpeed: _parseDouble(json['fan_speed']) ?? 0.0,
      timeLeft: _parseInt(json['timeLeft']) ?? 0,
      currentFile: json['currentFile'] as String?,
      progress: _parseDouble(json['progress']) ?? 0.0,
      currentLayer: _parseInt(json['currentLayer']) ?? 0,
      totalLayers: _parseInt(json['totalLayers']) ?? 0,
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
      final command = '${json.encode({
        'type': 'GET_STATUS'
      })}\n';
      sendCommand(command);
    });
  }

  Future<void> sendGCode(String gcode) async {
    if (!isConnected()) {
      throw Exception("프린터가 연결되어 있지 않습니다");
    }
    try {
      final gCodeWithNewline = gcode.endsWith('\n') ? gcode : '$gcode\n';
      _connection!.output.add(Uint8List.fromList(gCodeWithNewline.codeUnits));
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

          // 프린터 상태 업데이트 추가
          if (jsonResponse['data'] != null && jsonResponse['data']['status'] != null) {
            _printerStatus = PrinterStatus.fromJson(jsonResponse['data']['status']);
            notifyListeners();
          }

          if (jsonResponse['data'] != null &&
              jsonResponse['data']['temperatures'] != null) {
            final temps = jsonResponse['data']['temperatures'];
            _currentNozzleTemperature = temps['nozzle']?.toDouble();
            _currentBedTemperature = temps['bed']?.toDouble();

            if (_currentNozzleTemperature != null && _currentBedTemperature != null) {
              _temperatureHistory.add(TemperatureData(
                time: DateTime.now(),
                nozzleTemp: _currentNozzleTemperature!,
                bedTemp: _currentBedTemperature!,
                nozzleTargetTemp: 0.0, // 또는 실제 목표 온도
                bedTargetTemp: 0.0, // 또는 실제 목표 온도
              ));

              if (_temperatureHistory.length > _maxHistorySize) {
                _temperatureHistory.removeAt(0);
              }
            }
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
      throw Exception('블루투스가 연결되지 않습니다');
    }

    const int chunkSize = 1024;  // 청크 크기를 1KB로 감소
    try {
      // 파일 전송 시작 알림
      final startCommand = json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'start',
        'filename': filename,
        'total_size': fileContent.length
      });

      final startResponse = await _sendCommandAndWaitResponse(startCommand);
      final startJson = json.decode(startResponse);

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
          await sendCommand(json.encode({
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
        final command = json.encode({
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

      await sendCommand(json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'finish',
        'filename': filename
      }));

      onProgress?.call(1.0);
      print('Upload completed');
    } catch (e) {
      print('파일 업로드 실패: $e');
      try {
        await sendCommand(json.encode({
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

  Future<void> sendCommand(String command) async {
    if (!isConnected()) {
      throw Exception('블루투스가 연결되지 않았습니다');
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
}