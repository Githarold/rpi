import bluetooth
import json
import logging
import threading
import os
from .bt_commands import BTCommands, BTResponse

logger = logging.getLogger(__name__)

class BluetoothServer:
    def __init__(self, printer_manager, service_name="SCARA 3D Printer"):
        self.printer_manager = printer_manager
        self.server_sock = None
        self.client_sock = None
        self.is_running = True
        self.uuid = "00001101-0000-1000-8000-00805F9B34FB"
        self.service_name = service_name

    def setup_server(self):
        """블루투스 서버 설정"""
        try:
            if not os.access('/var/run/sdp', os.W_OK):
                logger.warning("No write permission for /var/run/sdp")
                os.system('sudo chmod 777 /var/run/sdp')
                
            self.server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
            port = bluetooth.PORT_ANY
            self.server_sock.bind(("", port))
            self.server_sock.listen(1)

            bluetooth.advertise_service(
                self.server_sock, 
                self.service_name,
                service_id=self.uuid,
                service_classes=[self.uuid, bluetooth.SERIAL_PORT_CLASS],
                profiles=[bluetooth.SERIAL_PORT_PROFILE]
            )
            logger.info(f"Bluetooth server started on RFCOMM channel {self.server_sock.getsockname()[1]}")
            return True
        except Exception as e:
            logger.error(f"Failed to setup bluetooth server: {e}")
            return False

    def handle_command(self, command_str):
        """수신된 명령 처리"""
        try:
            command = json.loads(command_str)
            cmd_type = command.get('type', '')

            logger.info(f"Received command: {cmd_type}")

            if cmd_type == BTCommands.START_PRINT.value:
                result = self.printer_manager.start_print(command.get('filename'))
                return json.dumps(result)

            elif cmd_type == BTCommands.PAUSE.value:
                result = self.printer_manager.pause_print()
                return json.dumps(result)

            elif cmd_type == BTCommands.RESUME.value:
                result = self.printer_manager.resume_print()
                return json.dumps(result)

            elif cmd_type == BTCommands.STOP.value:
                result = self.printer_manager.stop_print()
                return json.dumps(result)

            elif cmd_type == BTCommands.GET_STATUS.value:
                status = self.printer_manager.get_status()
                return json.dumps(BTResponse.success(data=status))

            elif cmd_type == BTCommands.UPLOAD_GCODE.value:
                result = self.printer_manager.upload_gcode(
                    command.get('filename'),
                    command.get('content')
                )
                return json.dumps(result)

            else:
                return json.dumps(BTResponse.error(f"Unknown command: {cmd_type}"))

        except json.JSONDecodeError:
            logger.error("Invalid JSON format received")
            return json.dumps(BTResponse.error("Invalid JSON format"))
        except Exception as e:
            logger.error(f"Error handling command: {e}")
            return json.dumps(BTResponse.error(str(e)))

    def handle_client(self, client_sock, client_info):
        """클라이언트 연결 처리"""
        logger.info(f"Client connected: {client_info}")

        while True:
            try:
                data = client_sock.recv(1024)
                if not data:
                    break

                received = data.decode('utf-8')
                logger.debug(f"Received data: {received}")

                response = self.handle_command(received)
                client_sock.send(response.encode('utf-8'))

            except Exception as e:
                logger.error(f"Error handling client: {e}")
                break

        logger.info(f"Client disconnected: {client_info}")
        client_sock.close()

    def start(self):
        """서버 시작"""
        if not self.setup_server():
            return

        try:
            while self.is_running:
                try:
                    client_sock, client_info = self.server_sock.accept()
                    client_thread = threading.Thread(
                        target=self.handle_client,
                        args=(client_sock, client_info)
                    )
                    client_thread.daemon = True
                    client_thread.start()
                except Exception as e:
                    logger.error(f"Error accepting connection: {e}")

        except KeyboardInterrupt:
            logger.info("Server stopping...")
        finally:
            self.cleanup()

    def cleanup(self):
        """리소스 정리"""
        self.is_running = False
        if self.server_sock:
            self.server_sock.close()
