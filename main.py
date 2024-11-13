import os
import sys
from pathlib import Path
from octo_src.utils import ConfigManager, setup_logger
from octo_src.bluetooth import BluetoothServer
from octo_src.octoprint import OctoPrintClient
from octo_src.gcode import GCodeManager

# 로거 설정을 가장 먼저 수행
logger = setup_logger(
    'mie_printer',
    log_file='logs/printer.log',
    error_log_file='logs/printer-error.log'
)

def main():
    # 설정 로드
    config = ConfigManager('config/config.json')

    try:
        # OctoPrint 클라이언트 초기화
        octoprint_client = OctoPrintClient(
            api_key=config.get('octoprint.api_key'),
            base_url=config.get('octoprint.base_url', 'http://localhost:5000')
        )
        
        # GCode 매니저 초기화
        gcode_manager = GCodeManager(
            upload_folder=config.get('upload.folder', '/home/c9lee/.octoprint/uploads')
        )
        
        # 블루투스 서버 초기화
        bt_server = BluetoothServer(
            octoprint_client=octoprint_client,
            gcode_manager=gcode_manager,
            service_name=config.get('bluetooth.service_name', 'MIE Printer')
        )

        # 서버 시작
        logger.info("Starting Bluetooth server...")
        bt_server.start()

    except KeyboardInterrupt:
        logger.info("Shutting down server...")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")

if __name__ == "__main__":
    main()