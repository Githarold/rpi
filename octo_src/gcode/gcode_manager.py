import os
import logging
import tempfile
import shutil

logger = logging.getLogger('mie_printer.gcode')

class GCodeManager:
    def __init__(self, upload_folder):
        self.upload_folder = upload_folder
        self.active_upload = None
        self.temp_file = None
        
        # 업로드 폴더가 없으면 생성
        if not os.path.exists(self.upload_folder):
            os.makedirs(self.upload_folder)
            logger.info(f"Created upload folder: {self.upload_folder}")

    def is_file_ready(self, filename):
        """파일이 이미 존재하고 사용 가능한지 확인"""
        try:
            full_path = os.path.join(self.upload_folder, filename)
            if os.path.exists(full_path):
                # 파일 크기가 0보다 크고 읽기 가능한지 확인
                return os.path.getsize(full_path) > 0 and os.access(full_path, os.R_OK)
            return False
        except Exception as e:
            logger.error(f"Error checking file readiness: {e}")
            return False

    def get_file_path(self, filename):
        """파일의 전체 경로 반환"""
        return os.path.join(self.upload_folder, filename)

    def init_upload(self, filename, total_size):
        """새로운 파일 업로드 초기화"""
        try:
            if self.is_file_ready(filename):
                # 파일이 이미 존재하면 성공으로 처리
                logger.info(f"File {filename} already exists and is ready")
                return True

            # 이전 업로드 세션 정리
            self._cleanup_upload()

            # 새 임시 파일 생성
            self.temp_file = tempfile.NamedTemporaryFile(delete=False)
            self.active_upload = {
                'filename': filename,
                'total_size': total_size,
                'received_size': 0
            }
            logger.debug(f"Upload initialized for {filename}")
            return True
        except Exception as e:
            logger.error(f"Error initializing upload: {e}")
            self._cleanup_upload()
            return False

    def append_chunk(self, chunk_data, chunk_index=0, total_chunks=1, is_last=True):
        """청크 데이터 추가"""
        try:
            if not self.active_upload or not self.temp_file:
                logger.error("No active upload session or temp file missing")
                return False

            self.temp_file.write(chunk_data.encode())
            self.active_upload['received_size'] += len(chunk_data)
            
            if is_last and self.active_upload['received_size'] >= self.active_upload['total_size']:
                return self.finalize_upload(self.active_upload['filename'])
                
            return True
        except Exception as e:
            logger.error(f"Error appending chunk: {e}")
            self._cleanup_upload()
            return False

    def finalize_upload(self, filename):
        """업로드 완료 및 파일 이동"""
        try:
            if not self.active_upload or not self.temp_file or self.active_upload['filename'] != filename:
                logger.error("Invalid upload session for finalization")
                return False

            # 임시 파일 닫기
            self.temp_file.close()

            # 최종 파일 경로 설정
            final_path = os.path.join(self.upload_folder, filename)

            # 임시 파일을 최종 위치로 이동
            shutil.move(self.temp_file.name, final_path)
            
            logger.info(f"Upload finalized: {filename}")
            self._cleanup_upload()
            return True
        except Exception as e:
            logger.error(f"Error finalizing upload: {e}")
            self._cleanup_upload()
            return False

    def _cleanup_upload(self):
        """업로드 세션 정리"""
        try:
            if self.temp_file:
                self.temp_file.close()
                if os.path.exists(self.temp_file.name):
                    os.unlink(self.temp_file.name)
        except Exception as e:
            logger.error(f"Error cleaning up upload: {e}")
        finally:
            self.active_upload = None
            self.temp_file = None