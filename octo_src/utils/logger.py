import logging
from logging.handlers import RotatingFileHandler
import os

def setup_logger(name, log_file=None, error_log_file=None, level=logging.INFO):
    """로거 설정
    
    Args:
        name: 로거 이름
        log_file: 일반 로그 파일 경로
        error_log_file: 에러 로그 파일 경로
        level: 로깅 레벨
    """
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    logger = logging.getLogger(name)
    logger.setLevel(level)
    
    # 이전 핸들러 제거
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)

    if log_file:
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        file_handler = RotatingFileHandler(
            log_file,
            maxBytes=1024 * 1024,
            backupCount=5
        )
        file_handler.setFormatter(formatter)
        file_handler.setLevel(logging.INFO)
        logger.addHandler(file_handler)

    if error_log_file:
        os.makedirs(os.path.dirname(error_log_file), exist_ok=True)
        error_handler = RotatingFileHandler(
            error_log_file,
            maxBytes=1024 * 1024,
            backupCount=5
        )
        error_handler.setFormatter(formatter)
        error_handler.setLevel(logging.ERROR)
        logger.addHandler(error_handler)

    return logger 