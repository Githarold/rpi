import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

abstract class FileService {
  Future<List<Map<String, String>>> getGCodeFiles(); // 여기를 수정
  Future<void> uploadGCodeFile(String filePath, String fileName);
  Future<void> deleteGCodeFile(String fileName);
  Future<void> uploadGCodeFileWeb(List<int> fileBytes, String fileName);
  Future<String> readGCodeFile(String fileName);
  Future<String> getGCodePreview(String fileName, int lines);
}

FileService getFileService() {
  if (kIsWeb) {
    return WebFileService();
  } else {
    return NativeFileService();
  }
}

class WebFileService implements FileService {
  final List<Map<String, String>> _webFiles = [
    {'name': 'example1.gcode', 'size': '1.0 KB', 'date': '2023-05-01'},
    {'name': 'example2.gcode', 'size': '2.5 KB', 'date': '2023-05-02'},
    {'name': 'example3.gcode', 'size': '3.7 KB', 'date': '2023-05-03'},
  ];

  @override
  Future<List<Map<String, String>>> getGCodeFiles() async {
    return _webFiles;
  }

  @override
  Future<void> uploadGCodeFile(String filePath, String fileName) async {
    throw UnimplementedError('웹에서는 uploadGCodeFile을 사용할 수 없습니다.');
  }

  @override
  Future<void> uploadGCodeFileWeb(List<int> fileBytes, String fileName) async {
    _webFiles.add({
      'name': fileName,
      'size': '${(fileBytes.length / 1024).toStringAsFixed(1)} KB',
      'date': DateTime.now().toString().split(' ')[0],
    });
  }

  @override
  Future<void> deleteGCodeFile(String fileName) async {
    _webFiles.removeWhere((file) => file['name'] == fileName);
  }

  @override
  Future<String> readGCodeFile(String fileName) async {
    // 웹에서는 파일 시스템에 직접 접근할 수 없으므로, 
    // 서버에서 파일 내용을 가져오는 로직을 구현해야 합니다.
    // 여기서는 예시로 더미 데이터를 반환합니다.
    return 'G1 X10 Y10 Z10\nG1 X20 Y20 Z20\n...';
  }

  @override
  Future<String> getGCodePreview(String fileName, int lines) async {
    final content = await readGCodeFile(fileName);
    final allLines = content.split('\n');
    return allLines.take(lines).join('\n');
  }
}

class NativeFileService implements FileService {
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  @override
  Future<List<Map<String, String>>> getGCodeFiles() async {
    final path = await _localPath;
    final dir = Directory(path);
    List<FileSystemEntity> entities = dir.listSync();
    List<Map<String, String>> files = [];

    for (var entity in entities) {
      if (entity is File && entity.path.toLowerCase().endsWith('.gcode')) {
        String fileName = entity.path.split('/').last;
        int fileSize = await entity.length();
        String fileSizeStr = _formatFileSize(fileSize);
        String fileDate = _formatFileDate(await entity.lastModified());
        
        files.add({
          'name': fileName,
          'size': fileSizeStr,
          'date': fileDate,
        });
      }
    }
    
    if (files.isEmpty) {
      files = [
        {'name': 'example1.gcode', 'size': '1.0 KB', 'date': '2023-05-01'},
        {'name': 'example2.gcode', 'size': '2.5 KB', 'date': '2023-05-02'},
        {'name': 'example3.gcode', 'size': '3.7 KB', 'date': '2023-05-03'},
      ];
    }
    
    return files;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatFileDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<void> uploadGCodeFile(String filePath, String fileName) async {
    final path = await _localPath;
    final file = File('$path/$fileName');
    await file.writeAsBytes(await File(filePath).readAsBytes());
    print('File saved at: $path/$fileName'); // 이 줄을 추가하세요
  }

  @override
  Future<void> uploadGCodeFileWeb(List<int> fileBytes, String fileName) async {
    // 네이티브 플랫폼에서는 사용되지 않음
    throw UnimplementedError('네이티브 플랫폼에서는 uploadGCodeFileWeb을 사용할 수 없습니다.');
  }

  @override
  Future<void> deleteGCodeFile(String fileName) async {
    final path = await _localPath;
    final file = File('$path/$fileName');
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<String> readGCodeFile(String fileName) async {
    final path = await _localPath;
    final file = File('$path/$fileName');
    print('Reading file content from: $path/$fileName');
    try {
      if (await file.exists()) {
        return await file.readAsString();
      } else {
        throw FileSystemException('파일을 찾을 수 없습니다: $fileName');
      }
    } catch (e) {
      print('파일 읽기 오류: $e');
      rethrow;
    }
  }

  @override
  Future<String> getGCodePreview(String fileName, int lines) async {
    final content = await readGCodeFile(fileName);
    final allLines = content.split('\n');
    return allLines.take(lines).join('\n');
  }
}
