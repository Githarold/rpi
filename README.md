

# MIE 3D 프린터 제어 시스템

## 개요
이 프로젝트는 라즈베리파이를 이용한 3D 프린터 제어 시스템입니다. 블루투스를 통해 모바일 앱에서 프린터를 제어할 수 있습니다.

## 주요 기능
- 블루투스 통신을 통한 프린터 제어
- G-code 파일 업로드 및 실행
- 실시간 프린터 상태 모니터링
- 시뮬레이션 모드 지원 (프린터 미연결 시)

## 시스템 요구사항
- Raspberry Pi (3 이상 권장)
- Python 3.7+
- Bluetooth 지원
- 필요한 Python 패키지:
  - pyserial
  - pybluez

## 설치 방법
1. 저장소 클론
```bash
git clone https://github.com/your-username/mie-printer.git
cd mie-printer
```

2. 설치 스크립트 실행
```bash
chmod +x install.sh
./install.sh
```

3. 시스템 재부팅
```bash
sudo reboot
```

## 프로젝트 구조
```
rpi/
├── src/
│   ├── bluetooth/     # 블루투스 통신 관련
│   ├── printer/       # 프린터 제어 로직
│   ├── serial/        # 시리얼 통신 관리
│   ├── gcode/         # G-code 파일 관리
│   └── utils/         # 유틸리티 함수
├── tests/             # 테스트 코드
├── config/            # 설정 파일
├── logs/              # 로그 파일
└── gcode_files/       # G-code 파일 저장소
```

## 주요 컴포넌트
1. BluetoothServer

```1:37:rpi/src/bluetooth/bt_server.py
import bluetooth
import json
import logging
import threading
from .bt_commands import BTCommands, BTResponse

logger = logging.getLogger(__name__)
```

- 블루투스 연결 및 통신 관리
- 클라이언트 명령어 처리

2. PrinterManager

```8:60:rpi/src/printer/printer_manager.py
class PrinterManager:
    def __init__(self, serial_manager, gcode_manager):
        self.serial_manager = serial_manager
        self.gcode_manager = gcode_manager
        self.status = PrinterStatus()
        self.is_running = True
        
        # 프린터 제어 스레드 시작
        self.printer_thread = threading.Thread(target=self._printer_control_loop)
        self.printer_thread.daemon = True
        self.printer_thread.start()

    def upload_gcode(self, filename, content):
        """G-code 파일 업로드"""
        try:
            if self.status.state != PrinterState.IDLE:
                return BTResponse.error("Printer is busy")

            if self.gcode_manager.save_gcode(filename, content):
                return BTResponse.success(message="File uploaded successfully")
            else:
                return BTResponse.error("Failed to save G-code file")

        except Exception as e:
            logger.error(f"Error uploading G-code: {e}")
            return BTResponse.error(str(e))

    def start_print(self, filename):
        """프린트 작업 시작"""
        try:
            if self.status.state != PrinterState.IDLE:
                return BTResponse.error("Printer is busy")

            if not self.gcode_manager.load_gcode(filename):
                return BTResponse.error("Failed to load G-code file")

            self.status.state = PrinterState.PRINTING
            self.status.current_file = filename
            self.status.progress = 0

            # 시작 명령 전송
            self.serial_manager.send_command("M110 N0")  # 라인 넘버 리셋
            self.serial_manager.send_command("M109 S200")  # 노즐 예열 (200도)
            self.serial_manager.send_command("M190 S60")   # 베드 예열 (60도)
            
            return BTResponse.success(message="Print started")

        except Exception as e:
            logger.error(f"Error starting print: {e}")
            self.status.state = PrinterState.ERROR
            self.status.error = str(e)
            return BTResponse.error(str(e))
```

- 프린터 상태 관리
- G-code 실행 제어

3. SerialManager

```7:54:rpi/src/serial/serial_manager.py
class SerialManager:
    def __init__(self, port='/dev/ttyUSB0', baudrate=115200):
        self.port = port
        self.baudrate = baudrate
        self.serial_conn = None
        self.lock = Lock()
        self.simulation_mode = False

    def close(self):
        """시리얼 연결 종료"""
        if self.serial_conn:
            self.serial_conn.close()
            self.serial_conn = None
        logger.info("Serial connection closed")

    def connect(self):
        try:
            self.serial_conn = serial.Serial(
                self.port,
                self.baudrate,
                timeout=1
            )
            logger.info(f"Serial connection established on {self.port}")
            self.simulation_mode = False
            return True
        except serial.SerialException as e:
            logger.warning(f"Failed to connect to Arduino: {e}. Running in simulation mode.")
            self.simulation_mode = True
            return True  # 연결 실패해도 True 반환

    def send_command(self, command):
        with self.lock:
            try:
                if self.simulation_mode:
                    logger.debug(f"Simulation mode - Command sent: {command}")
                    return "ok"  # 시뮬레이션 모드에서는 항상 "ok" 반환
                    
                if not self.serial_conn:
                    raise Exception("Serial connection not established")
                
                self.serial_conn.write(f"{command}\n".encode())
                response = self.serial_conn.readline().decode().strip()
                return response
            except Exception as e:
                if self.simulation_mode:
                    return "ok"
                logger.error(f"Error sending command: {e}")
                raise
```

- 시리얼 통신 관리
- 시뮬레이션 모드 지원

## 사용 방법
1. 서비스 상태 확인
```bash
./test.sh
```

2. 로그 확인
```bash
tail -f logs/printer.log
```