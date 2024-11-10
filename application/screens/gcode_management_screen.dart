import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/bluetooth_service.dart';
import '../services/file_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

class GCodeManagementScreen extends StatefulWidget {
  const GCodeManagementScreen({super.key});

  @override
  State<GCodeManagementScreen> createState() => _GCodeManagementScreenState();
}

class _GCodeManagementScreenState extends State<GCodeManagementScreen> {
  final FileService _fileService = getFileService();
  List<Map<String, String>> gcodeFiles = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      gcodeFiles = await _fileService.getGCodeFiles();
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('파일 로드 중 오류 발생: $e')),
        );
      }
      print('파일 로드 오류: $e'); // 로그 추가
    }
  }

  Future<void> _uploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null) {
        String fileName = result.files.single.name;
        if (fileName.toLowerCase().endsWith('.gcode')) {
          if (kIsWeb) {
            await _fileService.uploadGCodeFileWeb(result.files.single.bytes!, fileName);
          } else {
            await _fileService.uploadGCodeFile(result.files.single.path!, fileName);
          }
          await _loadFiles();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('파일이 성공적으로 업로드되었습니다.')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('G-code 파일만 업로드할 수 있습니다.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('파일 업로드 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _deleteFile(String fileName) async {
    try {
      await _fileService.deleteGCodeFile(fileName);
      setState(() {
        gcodeFiles.removeWhere((file) => file['name'] == fileName);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('파일 "$fileName"이(가) 삭제되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('파일 삭제 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _showFilePreview(String fileName) async {
    final preview = await _fileService.getGCodePreview(fileName, 10);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fileName),
        content: SingleChildScrollView(
          child: Text(preview),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _startPrinting(Map<String, String> file) async {
    final bluetoothService = Provider.of<BluetoothService>(context, listen: false);
    
    if (!bluetoothService.isConnected()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프린터가 연결되어 있지 않습니다.')),
        );
      }
      return;
    }

    try {
      double uploadProgress = 0.0;
      bool isUploading = true;
      
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return WillPopScope(
            onWillPop: () async => false,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: const Text('파일 전송 중'),
                  content: SizedBox(
                    width: 300,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('G-code 파일을 프린터로 전송하고 있습니다...'),
                        const SizedBox(height: 20),
                        LinearProgressIndicator(value: uploadProgress),
                        const SizedBox(height: 10),
                        Text('${(uploadProgress * 100).toStringAsFixed(1)}%'),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      );

      await bluetoothService.sendGCodeFile(
        file['name']!,
        context,
        (progress) {
          if (mounted) {
            setState(() {
              uploadProgress = progress;
              if (progress >= 1.0) {
                isUploading = false;
                Navigator.of(context).pop();
              }
            });
          }
        },
      );

      await bluetoothService.startPrint(file['name']!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('출력이 시작되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('출력 시작 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  void _confirmStartPrinting(Map<String, String> file) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('출력 시작 확인'),
          content: Text('"${file['name']}" 파일을 출력하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              child: const Text('취소'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('출력'),
              onPressed: () {
                Navigator.of(context).pop();
                _startPrinting(file);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('G-code 파일 관리'),
      ),
      body: ListView.builder(
        itemCount: gcodeFiles.length,
        itemBuilder: (context, index) {
          final file = gcodeFiles[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              title: Text(file['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Size: ${file['size']}'),
                  Text('Created: ${file['date']}'),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.print, color: Colors.blue),
                    onPressed: () => _confirmStartPrinting(file),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmDeleteFile(file['name'] ?? ''),
                  ),
                ],
              ),
              onTap: () => _showFilePreview(file['name'] ?? ''),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploadFile,
        tooltip: '파일 추가',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDeleteFile(String fileName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('파일 삭제 확인'),
          content: Text('정말로 "$fileName" 파일을 삭제하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              child: const Text('취소'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('삭제'),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteFile(fileName);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
