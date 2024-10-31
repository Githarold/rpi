import bluetooth
import json
import threading
from queue import Queue
import time

class BluetoothPrinterServer:
    def __init__(self):
        self.server_sock = None
        self.client_sock = None
        self.is_running = True
        self.message_queue = Queue()
        self.uuid = "00001101-0000-1000-8000-00805F9B34FB"
        
        # 프린터 상태 관리
        self.printer_state = {
            "status": "idle",
            "temperature": {
                "nozzle": 0,
                "bed": 0
            },
            "progress": 0
        }

    def setup_server(self):
        self.server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
        port = bluetooth.PORT_ANY
        self.server_sock.bind(("", port))
        self.server_sock.listen(1)

        bluetooth.advertise_service(
            self.server_sock, 
            "SCARA 3D Printer",
            service_id=self.uuid,
            service_classes=[self.uuid, bluetooth.SERIAL_PORT_CLASS],
            profiles=[bluetooth.SERIAL_PORT_PROFILE]
        )

        print(f"Waiting for connection on RFCOMM channel {self.server_sock.getsockname()[1]}")

    def handle_command(self, command_str):
        try:
            command = json.loads(command_str)
            cmd_type = command.get('type', '')
            
            response = {"status": "ok"}
            
            if cmd_type == "START_PRINT":
                self.printer_state["status"] = "printing"
                response["message"] = "Print started"
                
            elif cmd_type == "PAUSE":
                self.printer_state["status"] = "paused"
                response["message"] = "Print paused"
                
            elif cmd_type == "RESUME":
                self.printer_state["status"] = "printing"
                response["message"] = "Print resumed"
                
            elif cmd_type == "STOP":
                self.printer_state["status"] = "idle"
                response["message"] = "Print stopped"
                
            elif cmd_type == "GET_STATUS":
                response["data"] = self.printer_state
                
            else:
                response = {
                    "status": "error",
                    "message": f"Unknown command: {cmd_type}"
                }
                
            return json.dumps(response)
            
        except json.JSONDecodeError:
            return json.dumps({
                "status": "error",
                "message": "Invalid JSON format"
            })

    def update_status(self):
        """프린터 상태 주기적 업데이트"""
        while self.is_running:
            if self.printer_state["status"] == "printing":
                self.printer_state["progress"] += 1
                if self.printer_state["progress"] >= 100:
                    self.printer_state["status"] = "idle"
                    self.printer_state["progress"] = 0
                
                # 여기에 실제 온도 읽기 로직 추가
                # self.printer_state["temperature"]["nozzle"] = read_nozzle_temp()
                # self.printer_state["temperature"]["bed"] = read_bed_temp()
                
            time.sleep(1)

    def client_handler(self, client_sock, client_info):
        print(f"Accepted connection from {client_info}")
        
        try:
            while True:
                data = client_sock.recv(1024)
                if not data:
                    break
                    
                received = data.decode('utf-8')
                print(f"Received: {received}")
                
                response = self.handle_command(received)
                client_sock.send(response.encode('utf-8'))
                
        except OSError as e:
            print(f"Error handling client: {e}")
        finally:
            print("Disconnected")
            client_sock.close()

    def run(self):
        self.setup_server()
        
        # 상태 업데이트 스레드 시작
        status_thread = threading.Thread(target=self.update_status)
        status_thread.daemon = True
        status_thread.start()
        
        try:
            while self.is_running:
                client_sock, client_info = self.server_sock.accept()
                client_thread = threading.Thread(
                    target=self.client_handler,
                    args=(client_sock, client_info)
                )
                client_thread.daemon = True
                client_thread.start()
                
        except KeyboardInterrupt:
            print("\nShutting down server...")
        finally:
            self.is_running = False
            if self.server_sock:
                self.server_sock.close()
            print("Server stopped")

if __name__ == "__main__":
    server = BluetoothPrinterServer()
    server.run()