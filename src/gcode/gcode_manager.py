import os
import logging
import base64
from pathlib import Path

logger = logging.getLogger(__name__)

MAX_FILE_SIZE = 100 * 1024 * 1024  # 100MB 제한

class GCodeManager:
    def __init__(self, gcode_folder='/home/c9lee/rpi/gcode_files'):
        self.gcode_folder = Path(gcode_folder)
        self.gcode_folder.mkdir(parents=True, exist_ok=True)
        self.temp_file = None
        self.received_size = 0
        self.total_size = 0
        self.current_file = None
        self.current_lines = None
        self.current_line_number = 0
    
    def init_upload(self, filename, total_size):
        """파일 업로드 초기화"""
        if total_size > MAX_FILE_SIZE:
            logger.error(f"File size {total_size} exceeds maximum allowed size {MAX_FILE_SIZE}")
            return False
        self.temp_file = self.gcode_folder / f"{filename}.temp"
        self.expected_size = total_size
        self.received_size = 0
        return True

    def append_chunk(self, chunk_data, chunk_index=0, total_chunks=1, is_last=True):
        """청크 데이터 추가"""
        try:
            # URL-safe base64 디코딩을 위한 패딩 복원
            chunk_data = chunk_data.replace('-', '+').replace('_', '/')
            padding = 4 - (len(chunk_data) % 4)
            if padding != 4:
                chunk_data += '=' * padding
            
            # base64 디코딩
            decoded_data = base64.b64decode(chunk_data)
            with open(self.temp_file, 'ab') as f:
                f.write(decoded_data)
            self.received_size += len(decoded_data)
            
            # 마지막 청크인 경우에만 파일 크기 검증
            if is_last and chunk_index == total_chunks - 1:  # 마지막 패킷인 경우에만 검증
                if self.received_size != self.expected_size:
                    logger.error(f"Final size mismatch: received {self.received_size}, expected {self.expected_size}")
                    return False
            else:
                # 진행 상황 로깅 (로그 레벨을 INFO로 변경)
                logger.info(f"Received chunk {chunk_index}/{total_chunks}, size: {len(decoded_data)}, total received: {self.received_size}")
            
            return True
        except Exception as e:
            logger.error(f"Error appending chunk: {e}")
            return False

    def finalize_upload(self, filename):
        """파일 업로드 완료"""
        try:
            if self.received_size != self.expected_size:
                logger.error(f"Size mismatch at finalization: received {self.received_size}, expected {self.expected_size}")
                if self.temp_file.exists():
                    self.temp_file.unlink()
                return False
                
            final_path = self.gcode_folder / filename
            if final_path.exists():
                final_path.unlink()  # 기존 파일이 있다면 삭제
            self.temp_file.rename(final_path)
            logger.info(f"Successfully uploaded file {filename} ({self.received_size} bytes)")
            return True
        except Exception as e:
            logger.error(f"Error finalizing upload: {e}")
            if self.temp_file and self.temp_file.exists():
                try:
                    self.temp_file.unlink()
                except Exception as e2:
                    logger.error(f"Error cleaning up temp file: {e2}")
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