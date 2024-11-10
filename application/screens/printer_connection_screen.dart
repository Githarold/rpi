import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';

class PrinterConnectionScreen extends StatefulWidget {
  const PrinterConnectionScreen({super.key});

  @override
  State<PrinterConnectionScreen> createState() => _PrinterConnectionScreenState();
}

class _PrinterConnectionScreenState extends State<PrinterConnectionScreen> {
  List<BluetoothDevice> _pairedDevices = [];
  final List<BluetoothDiscoveryResult> _discoveredDevices = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initializeDevices();
  }

  Future<void> _initializeDevices() async {
    await _getPairedDevices();
  }

  Future<void> _getPairedDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        _pairedDevices = devices;
      });
    } catch (error) {
      print('페어링된 기기를 가져오는 중 오류 발생: $error');
    }
  }

  Future<void> _scanForDevices() async {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    try {
      await for (final r in FlutterBluetoothSerial.instance.startDiscovery()) {
        if (!mounted) break;
        setState(() {
          final existingIndex = _discoveredDevices.indexWhere((element) => element.device.address == r.device.address);
          if (existingIndex >= 0) {
            _discoveredDevices[existingIndex] = r;
          } else {
            _discoveredDevices.add(r);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${device.name}에 연결 중...')),
    );

    final bluetoothService = Provider.of<BluetoothService>(context, listen: false);
    bool connected = await bluetoothService.connectToPrinter(device.address);
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    if (connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('프린터에 연결되었습니다: ${device.name}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('프린터에 연결할 수 없습니다: ${device.name}. 다시 시도해주세요.'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '재시도',
            onPressed: () => _connectToDevice(device),
          ),
        ),
      );
    }
  }

  Widget _buildDeviceList(String title, List<BluetoothDevice> devices) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text(device.name ?? '알 수 없는 기기', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(device.address),
                trailing: IconButton(
                  icon: const Icon(Icons.bluetooth, color: Colors.blue),
                  onPressed: () => _connectToDevice(device),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('프린터 연결'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDeviceList('페어링된 기기', _pairedDevices),
            const SizedBox(height: 16),
            _buildDeviceList('발견된 기기', _discoveredDevices.map((r) => r.device).toList()),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: _isScanning ? null : _scanForDevices,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: Text(_isScanning ? '스캔 중...' : '주변 기기 찾기'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}