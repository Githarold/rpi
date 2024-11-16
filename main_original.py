from src.bluetooth import BluetoothServer
from src.printer import PrinterManager
from src.serial import SerialManager
from src.gcode import GCodeManager
from src.utils import ConfigManager, setup_logger

def main():
    # 설정 로드
    config = ConfigManager('config/config.json')
    
    # 로거 설정
    logger = setup_logger(
        'scara_printer',
        'logs/printer.log'
    )

    serial_manager = None  # 여기서 변수 초기화

    try:
        # 각 매니저 초기화
        serial_manager = SerialManager(
            port=config.get('serial.port'),
            baudrate=config.get('serial.baudrate', 115200)
        )
        gcode_manager = GCodeManager('gcode_files')
        printer_manager = PrinterManager(serial_manager, gcode_manager)
        bt_server = BluetoothServer(
            printer_manager,
            service_name=config.get('bluetooth.service_name', 'MIE Printer')
        )

        # 연결 설정
        if not serial_manager.connect():
            logger.error("Failed to connect to printer")
            return

        # 서버 시작
        bt_server.start()

    except KeyboardInterrupt:
        logger.info("Shutting down server...")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
    finally:
        if serial_manager:
            serial_manager.close()

if __name__ == "__main__":
    main()