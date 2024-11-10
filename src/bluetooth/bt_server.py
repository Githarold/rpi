import bluetooth
import json
import logging
import threading
import os
from .bt_commands import BTCommands, BTResponse

logger = logging.getLogger(__name__)

class BluetoothServer:

    def __init__(self, printer_manager, service_name="SCARA 3D Printer"):
        self.MAX_FILE_SIZE = 100 * 1024 * 1024  # 100MB 제한
        self.printer_manager = printer_manager
        self.server_sock = None
        self.client_sock = None
        self.is_running = True
        self.uuid = "00001101-0000-1000-8000-00805F9B34FB"
        self.service_name = service_name

    def setup_server(self):
        """블루투스 서버 설정"""
        try:
            if not os.path.exists('/var/run/sdp'):
                logger.warning("SDP directory does not exist")
                os.system('sudo mkdir -p /var/run/sdp')
        
            os.system('sudo chmod -R 777 /var/run/sdp')
            logger.info("SDP permissions set")
                
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
            if not command_str or not command_str.strip():
                return json.dumps(BTResponse.error("Empty command"))
                
            command_str = command_str.strip()
            
            try:
                command = json.loads(command_str)
            except json.JSONDecodeError as e:
                logger.error(f"JSON parsing error: {e}, Raw data: {command_str}")
                return json.dumps(BTResponse.error(f"Invalid JSON format: {str(e)}"))

            cmd_type = command.get('type')
            action = command.get('action')
            
            if cmd_type == 'UPLOAD_GCODE':
                if action == 'start':
                    filename = command.get('filename')
                    total_size = command.get('total_size')
                    if not filename or not total_size:
                        return json.dumps(BTResponse.error("Missing filename or total_size"))
                    success = self.printer_manager.gcode_manager.init_upload(filename, total_size)
                    if not success:
                        return json.dumps(BTResponse.error("Failed to initialize upload"))
                    return json.dumps(BTResponse.success(message="Upload initialized"))
                    
                elif action == 'chunk':
                    chunk_data = command.get('data')
                    chunk_index = command.get('chunk_index', 0)
                    total_chunks = command.get('total_chunks', 1)
                    is_last = command.get('is_last', True)
                    
                    if not chunk_data:
                        return json.dumps(BTResponse.error("Empty chunk data"))
                        
                    success = self.printer_manager.gcode_manager.append_chunk(
                        chunk_data, 
                        chunk_index=chunk_index,
                        total_chunks=total_chunks,
                        is_last=is_last
                    )
                    if not success:
                        return json.dumps(BTResponse.error("Failed to append chunk"))
                    return json.dumps(BTResponse.success(message="Chunk received"))
                    
                elif action == 'finish':
                    filename = command.get('filename')
                    if not filename:
                        return json.dumps(BTResponse.error("Missing filename"))
                    success = self.printer_manager.gcode_manager.finalize_upload(filename)
                    if not success:
                        return json.dumps(BTResponse.error("Failed to finalize upload"))
                    return json.dumps(BTResponse.success(message="Upload completed"))

            elif cmd_type == BTCommands.START_PRINT.value:
                filename = command.get('filename')
                if self.printer_manager.gcode_manager.is_file_ready(filename):
                    result = self.printer_manager.start_print(filename)
                    return json.dumps(result)
                else:
                    return json.dumps(BTResponse.error("File not ready or incomplete"))

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

            else:
                return json.dumps(BTResponse.error(f"Unknown command: {cmd_type}"))

        except Exception as e:
            logger.error(f"Error handling command: {e}")
            return json.dumps(BTResponse.error(str(e)))

    def handle_client(self, client_sock, client_info):
        data_buffer = ""
        try:
            while True:
                data = client_sock.recv(1024).decode('utf-8')
                if not data:
                    break
                data_buffer += data

                while '\n' in data_buffer:
                    message, data_buffer = data_buffer.split('\n', 1)
                    response = self.handle_command(message)
                    client_sock.send((response + '\n').encode('utf-8'))
        except Exception as e:
            logger.error(f"Error handling client {client_info}: {e}")
        finally:
            client_sock.close()
            logger.info(f"Connection with {client_info} closed.")

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
