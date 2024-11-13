import os
import logging
import base64
from pathlib import Path

logger = logging.getLogger(__name__)

class GCodeManager:
    def __init__(self, upload_folder='/home/c9lee/.octoprint/uploads'):
        self.upload_folder = Path(upload_folder)
        self.upload_folder.mkdir(parents=True, exist_ok=True)
        self.temp_file = None
        self.received_size = 0
        self.total_size = 0
    
    def init_upload(self, filename, total_size):
        """파일 업로드 초기화"""
        try:
            self.temp_file = self.upload_folder / f"{filename}.temp"
            self.expected_size = total_size
            self.received_size = 0
            return True
        except Exception as e:
            logger.error(f"Failed to initialize upload: {e}")
            return False

    def append_chunk(self, chunk_data, chunk_index=0, total_chunks=1, is_last=True):
        """청크 데이터 추가"""
        try:
            # URL-safe base64 디코딩
            chunk_data = chunk_data.replace('-', '+').replace('_', '/')
            padding = 4 - (len(chunk_data) % 4)
            if padding != 4:
                chunk_data += '=' * padding
            
            decoded_data = base64.b64decode(chunk_data)
            with open(self.temp_file, 'ab') as f:
                f.write(decoded_data)
            self.received_size += len(decoded_data)
            
            if is_last and self.received_size != self.expected_size:
                logger.error(f"Size mismatch: received {self.received_size}, expected {self.expected_size}")
                return False
                
            return True
        except Exception as e:
            logger.error(f"Error appending chunk: {e}")
            return False

    def finalize_upload(self, filename):
        """파일 업로드 완료"""
        try:
            if self.received_size != self.expected_size:
                logger.error(f"Size mismatch at finalization")
                if self.temp_file.exists():
                    self.temp_file.unlink()
                return False
                
            final_path = self.upload_folder / filename
            if final_path.exists():
                final_path.unlink()
            self.temp_file.rename(final_path)
            logger.info(f"Successfully uploaded file {filename}")
            return True
        except Exception as e:
            logger.error(f"Error finalizing upload: {e}")
            if self.temp_file and self.temp_file.exists():
                try:
                    self.temp_file.unlink()
                except Exception:
                    pass
            return False

    def is_file_ready(self, filename):
        """파일이 완전히 전송되었는지 확인"""
        try:
            file_path = self.upload_folder / filename
            return file_path.exists()
        except Exception as e:
            logger.error(f"Error checking file status: {e}")
            return False 