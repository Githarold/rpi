import os
import sys
from pathlib import Path
from octo_src.utils import ConfigManager, setup_logger
from octo_src.bluetooth import BluetoothServer
from octo_src.octoprint import OctoPrintClient
from octo_src.octoprint.temp_monitor import TemperatureMonitor
from octo_src.gcode import GCodeManager
import time

# 로거 설정을 가장 먼저 수행
logger = setup_logger(
    'mie_printer',
    log_file='/home/c9lee/rpi/logs/printer.log',
    error_log_file='/home/c9lee/rpi/logs/printer-error.log'
)

def check_printer_connection(octoprint_client):
    """프린터 연결 상태 확인 및 재연결 시도"""
    connection_status = octoprint_client.check_connection()
    if not connection_status:
        logger.error("Failed to get connection status")
        return False
        
    current_state = connection_status.get('current', {}).get('state')
    if current_state != 'Operational':
        logger.warning(f"Printer is not operational (state: {current_state}). Attempting to connect...")
        
        # 연결 시도
        if octoprint_client.connect_printer():
            logger.info("Successfully connected to printer")
            return True
        else:
            logger.error("Failed to connect to printer")
            return False
    
    return True

def main():
    # 설정 로드
    config = ConfigManager('/home/c9lee/rpi/config/config.json')

    try:
        # OctoPrint 클라이언트 초기화
        octoprint_client = OctoPrintClient(
            api_key=config.get('octoprint.api_key'),
            base_url=config.get('octoprint.base_url', 'http://localhost:5000')
        )
        
        # 프린터 연결 상태 확인
        if not check_printer_connection(octoprint_client):
            logger.error("Unable to establish printer connection. Exiting...")
            return
        
        # 온도 모니터 초기화 및 시작
        temp_monitor = TemperatureMonitor(octoprint_client)
        temp_monitor.start()
        
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
        if 'temp_monitor' in locals():
            temp_monitor.stop()
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        if 'temp_monitor' in locals():
            temp_monitor.stop()

if __name__ == "__main__":
    main()