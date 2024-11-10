import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'package:flutter/services.dart' show rootBundle;

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  Map<String, String> dependencies = {};
  String flutterVersion = '';

  @override
  void initState() {
    super.initState();
    _loadDependencies();
  }

  Future<void> _loadDependencies() async {
    final yamlString = await rootBundle.loadString('pubspec.yaml');
    final yamlMap = loadYaml(yamlString);
    final deps = yamlMap['dependencies'] as YamlMap;
    final environment = yamlMap['environment'] as YamlMap;

    setState(() {
      dependencies = Map<String, String>.from(deps.map((key, value) {
        if (value is String) {
          return MapEntry(key, value);
        } else if (value is YamlMap) {
          return MapEntry(key, value['version'] ?? 'Unknown');
        }
        return MapEntry(key, 'Unknown');
      }));

      // Flutter SDK 버전 정보 추가
      flutterVersion = environment['sdk'] ?? 'Unknown';
      dependencies['flutter'] = '3.24.3'; // Flutter SDK 버전을 수동으로 설정
    });
  }

  void _showPackageInfo(String packageName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(packageName),
        content: Text('버전: ${dependencies[packageName]}\n\n패키지 정보는 pub.dev에서 확인할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('오픈소스 라이선스'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '사용된 오픈소스 라이브러리',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                '이 앱은 다음 오픈소스 라이브러리를 사용합니다:',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: dependencies.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final entry = dependencies.entries.elementAt(index);
                    return ListTile(
                      title: Text(
                        entry.key,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('버전: ${entry.value}'),
                      trailing: const Icon(Icons.info_outline),
                      onTap: () => _showPackageInfo(entry.key),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '각 라이브러리를 탭하면 해당 라이브러리의 pub.dev 페이지로 이동합니다.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
