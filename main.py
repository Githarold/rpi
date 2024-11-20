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

def check_printer_connection(octoprint_client, max_retries=3, retry_delay=5):
    """프린터 연결 상태 확인 및 재연결 시도"""
    for attempt in range(max_retries):
        try:
            connection_status = octoprint_client.check_connection()
            if not connection_status:
                logger.error(f"Failed to get connection status (attempt {attempt + 1}/{max_retries})")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
                return False
            
            current_state = connection_status.get('current', {}).get('state')
            if current_state != 'Operational':
                logger.warning(f"Printer is not operational (state: {current_state}). Attempting to connect...")
                
                if octoprint_client.connect_printer():
                    logger.info("Successfully connected to printer")
                    return True
                elif attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
                else:
                    logger.error("Failed to connect to printer after all attempts")
                    return False
            
            return True
            
        except Exception as e:
            logger.error(f"Connection attempt {attempt + 1} failed: {str(e)}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                return False
    
    return False

def wait_for_octoprint(base_url, api_key, max_attempts=None, delay=5):
    """OctoPrint 서버가 준비될 때까지 무한 대기"""
    import requests
    from requests.exceptions import RequestException
    
    logger.info("Waiting for OctoPrint to become available...")
    attempt = 0
    
    while True:
        try:
            response = requests.get(f"{base_url}/api/version", headers={"X-Api-Key": api_key})
            if response.status_code == 200:
                logger.info("OctoPrint is now available")
                return True
        except RequestException as e:
            if max_attempts is not None:
                attempt += 1
                if attempt >= max_attempts:
                    logger.error("Failed to connect to OctoPrint after maximum attempts")
                    return False
            logger.debug(f"OctoPrint not ready (attempt {attempt}): {str(e)}")
        
        time.sleep(delay)

def wait_for_printer_connection(octoprint_client, max_retries=12, retry_delay=5):
    """프린터 연결이 설정될 때까지 대기"""
    logger.info("Waiting for printer connection...")
    
    retry_count = 0
    while retry_count < max_retries:
        if check_printer_connection(octoprint_client):
            logger.info("Printer connection established")
            return True
        
        retry_count += 1
        if retry_count < max_retries:
            logger.info(f"Retrying printer connection in {retry_delay} seconds... (attempt {retry_count}/{max_retries})")
            time.sleep(retry_delay)
    
    return False

def main():
    # 설정 로드
    config = ConfigManager('/home/c9lee/rpi/config/config.json')
    base_url = config.get('octoprint.base_url', 'http://localhost:5000')
    api_key = config.get('octoprint.api_key')

    # OctoPrint 서버가 준비될 때까지 대기
    if not wait_for_octoprint(base_url, api_key, max_attempts=None):
        logger.error("Could not connect to OctoPrint. Exiting...")
        return

    try:
        # OctoPrint 클라이언트 초기화
        octoprint_client = OctoPrintClient(
            api_key=config.get('octoprint.api_key'),
            base_url=base_url
        )
        
        # 프린터 연결 확인 및 재시도
        if not wait_for_printer_connection(octoprint_client):
            logger.error("Could not establish printer connection. Exiting...")
            return

        # 온도 모니터 초기화 및 시작
        temp_monitor = TemperatureMonitor(octoprint_client)
        temp_monitor.start()
        
        # GCode 매니저 초기화
        gcode_manager = GCodeManager(
            upload_folder=config.get('upload.folder') or '/home/c9lee/.octoprint/uploads'
        )
        
        # 블루투스 서버 초기화 (temp_monitor 전달)
        bt_server = BluetoothServer(
            octoprint_client=octoprint_client,
            gcode_manager=gcode_manager,
            temp_monitor=temp_monitor,
            service_name=config.get('bluetooth.service_name')
        )

        # 서버 시작
        bt_server.start()

    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        if 'temp_monitor' in locals():
            temp_monitor.stop()

if __name__ == "__main__":
    main()