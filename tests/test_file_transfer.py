import os
import json
from bluetooth import *
from pathlib import Path

class TestFileTransferServer:
    def __init__(self, save_path="test_files"):
        self.save_path = Path(save_path)
        self.save_path.mkdir(exist_ok=True)
        self.current_file = None
        
    def handle_command(self, data):
        try:
            command = json.loads(data)
            cmd_type = command.get('type', '')
            
            if cmd_type == "TRANSFER_START":
                self.current_file = {
                    'name': command['fileName'],
                    'size': command['fileSize'],
                    'path': self.save_path / command['fileName']
                }
                print(f"파일 전송 시작: {self.current_file['name']}")
                return True
                
            elif cmd_type == "TRANSFER_COMPLETE":
                if self.current_file:
                    actual_size = os.path.getsize(self.current_file['path'])
                    expected_size = self.current_file['size']
                    print(f"파일 전송 완료: {self.current_file['name']}")
                    print(f"예상 크기: {expected_size}, 실제 크기: {actual_size}")
                    self.current_file = None
                return True
                
        except json.JSONDecodeError:
            # 일반 데이터로 처리
            if self.current_file:
                with open(self.current_file['path'], 'ab') as f:
                    f.write(data.encode() if isinstance(data, str) else data)
            return True
            
        return False

    def run(self):
        server_sock = BluetoothSocket(RFCOMM)
        port = 1
        server_sock.bind(("", port))
        server_sock.listen(1)
        
        print("테스트 서버 시작...")
        print("포트:", port)
        
        while True:
            print("연결 대기 중...")
            client_sock, address = server_sock.accept()
            print(f"연결됨: {address}")
            
            try:
                while True:
                    data = client_sock.recv(1024)
                    if not data:
                        break
                    self.handle_command(data)
                    
            except Exception as e:
                print(f"오류 발생: {e}")
                
            finally:
                client_sock.close()
                
        server_sock.close()

if __name__ == "__main__":
    server = TestFileTransferServer()
    server.run() 