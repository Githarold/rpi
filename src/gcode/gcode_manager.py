import os
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

class GCodeManager:
    def __init__(self, gcode_folder):
        self.gcode_folder = Path(gcode_folder)
        self.gcode_folder.mkdir(exist_ok=True)
        self.current_file = None
        self.current_lines = None
        self.current_line_number = 0
    
    def init_upload(self, filename, total_size):
        if total_size > MAX_FILE_SIZE:
            return False
        self.temp_file = self.gcode_folder / f"{filename}.temp"
        self.expected_size = total_size
        self.received_size = 0
        return True

    def append_chunk(self, chunk_data):
        try:
            with open(self.temp_file, 'ab') as f:
                f.write(chunk_data)
            self.received_size += len(chunk_data)
            return True
        except Exception as e:
            logger.error(f"Error appending chunk: {e}")
            return False

    def finalize_upload(self, filename):
        try:
            if self.received_size != self.expected_size:
                self.temp_file.unlink()
                return False
                
            final_path = self.gcode_folder / filename
            self.temp_file.rename(final_path)
            return True
        except Exception as e:
            logger.error(f"Error finalizing upload: {e}")
            return False        

    def save_gcode(self, filename, content):
        try:
            file_path = self.gcode_folder / filename
            with open(file_path, 'w') as f:
                f.write(content)
            logger.info(f"Successfully saved G-code file: {filename}")
            return True
        except Exception as e:
            logger.error(f"Error saving G-code file: {e}")
            return False

    def load_gcode(self, filename):
        try:
            file_path = self.gcode_folder / filename
            with open(file_path, 'r') as f:
                self.current_lines = [line.strip() for line in f.readlines()]
                self.current_file = filename
                self.current_line_number = 0
            return True
        except Exception as e:
            logger.error(f"Error loading G-code file: {e}")
            return False

    def get_next_command(self):
        if not self.current_lines:
            return None

        while self.current_line_number < len(self.current_lines):
            line = self.current_lines[self.current_line_number].strip()
            self.current_line_number += 1
            
            if line and not line.startswith(';'):
                return line

        return None

    def get_progress(self):
        if not self.current_lines:
            return 0
        return (self.current_line_number / len(self.current_lines)) * 100

    def save_gcode_chunk(self, filename, content, chunk_number, total_chunks):
        try:
            temp_file_path = self.gcode_folder / f"{filename}.part{chunk_number}"
            with open(temp_file_path, 'w') as f:
                f.write(content)
            
            # 모든 청크가 수신되었는지 확인
            if chunk_number == total_chunks:
                final_content = []
                # 모든 청크 파일을 순서대로 합치기
                for i in range(1, total_chunks + 1):
                    chunk_path = self.gcode_folder / f"{filename}.part{i}"
                    with open(chunk_path, 'r') as f:
                        final_content.extend(f.readlines())
                    chunk_path.unlink()  # 임시 파일 삭제
                
                # 최종 파일 저장
                final_path = self.gcode_folder / filename
                with open(final_path, 'w') as f:
                    f.writelines(final_content)
                
                return True
            return True
            
        except Exception as e:
            logger.error(f"Error saving G-code chunk: {e}")
            return False

    def is_file_ready(self, filename):
        """파일이 완전히 전송되었는지 확인"""
        try:
            file_path = self.gcode_folder / filename
            return file_path.exists() and not any(
                self.gcode_folder.glob(f"{filename}.part*")
            )
        except Exception as e:
            logger.error(f"Error checking file status: {e}")
            return False