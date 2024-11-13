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
      // 개행 문자로 분리된 여러 응답을 처리
      List<String> responses = responseStr.split('\n');

      for (String response in responses) {
        if (response.trim().isEmpty) continue;

        try {
          Map<String, dynamic> jsonResponse = json.decode(response.trim());

          // 상태 업데이트 처리
          if (jsonResponse['data'] != null &&
              jsonResponse['data']['temperatures'] != null) {
            final temps = jsonResponse['data']['temperatures'];
            _currentNozzleTemperature = temps['nozzle']?.toDouble();
            _currentBedTemperature = temps['bed']?.toDouble();

            if (_currentNozzleTemperature != null && _currentBedTemperature != null) {
              _temperatureHistory.add(TemperatureData(
                  DateTime.now(),
                  _currentNozzleTemperature!,
                  _currentBedTemperature!
              ));

              // 히스토리 크기 제한
              if (_temperatureHistory.length > _maxHistorySize) {
                _temperatureHistory.removeAt(0);
              }
            }
            notifyListeners();
          }
        } catch (e) {
          if (response.trim().isNotEmpty) {
            print('JSON 파싱 오류: $e\n응답: $response');
          }
        }
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
    _connectionStatus = '연 안';
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

      // 파일 전송 시 알림
      final startCommand = '${json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'start',
        'filename': fileName,
        'total_size': fileBytes.length
      })}\n';

      await sendGCode(startCommand);

      // 청크 단위로 파일 전송
      for (var i = 0; i < fileBytes.length; i += chunkSize) {
        final end = min(i + chunkSize, fileBytes.length);
        final chunk = fileBytes.sublist(i, end);

        final chunkCommand = json.encode({
          'type': 'UPLOAD_GCODE',
          'action': 'chunk',
          'data': base64Encode(chunk)
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
      await sendCommand(json.encode({
        'type': 'UPLOAD_GCODE',
        'action': 'start',
        'filename': filename,
        'total_size': fileContent.length
      }));

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