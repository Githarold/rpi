import subprocess
import os
import serial
import time

# Arduino CLI 경로 및 보드 정보 설정
arduino_cli_path = "/home/c9lee/bin/arduino-cli"
fqbn_mega = "arduino:avr:mega"
port = "/dev/ttyACM0"
baud_rate = 115200

# 프로젝트 경로 설정
homing_path = "/home/c9lee/juicyMIE_Marlin/homing"
marlin_path = "/home/c9lee/juicyMIE_Marlin/Marlin-2.1.2.4/Marlin"

# 빌드 디렉토리 기본 경로
base_build_dir = "/home/c9lee/arduino_build_cache"

def reset_serial_port():
    """시리얼 포트를 강제로 초기화"""
    try:
        with serial.Serial(port, baud_rate, timeout=1) as ser:
            ser.setDTR(False)
            time.sleep(1)
            ser.flushInput()
            ser.setDTR(True)
            print("Serial 포트 초기화 완료.")
    except serial.SerialException as e:
        print(f"Serial 초기화 실패: {e}")

def wait_for_port():
    """시리얼 포트가 준비될 때까지 대기"""
    while True:
        try:
            with serial.Serial(port, baud_rate, timeout=1) as ser:
                if ser.is_open:
                    print(f"{port} 연결 성공!")
                    break
        except serial.SerialException:
            print(f"{port} 기다리는 중...")
            time.sleep(1)

def compile_and_upload(sketch_path, sketch_name):
    """Arduino 스케치 컴파일 및 업로드"""
    build_dir = os.path.join(base_build_dir, sketch_name)
    binary_path = os.path.join(build_dir, f"{sketch_name}.ino.hex")
    start_time = time.time()

    try:
        wait_for_port()
        reset_serial_port()
        os.makedirs(build_dir, exist_ok=True)

        sketch_mtime = os.path.getmtime(sketch_path)
        binary_mtime = os.path.getmtime(binary_path) if os.path.exists(binary_path) else 0

        if binary_mtime >= sketch_mtime:
            print(f"기존 컴파일 결과를 재사용하여 업로드 중: {sketch_name}")
            upload_process = subprocess.Popen(
                [arduino_cli_path, "upload", "-p", port, "--fqbn", fqbn_mega, "--input-file", binary_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            time.sleep(2)
            stdout, stderr = upload_process.communicate()
            if upload_process.returncode != 0:
                raise subprocess.CalledProcessError(upload_process.returncode, "upload", stderr)
        else:
            print(f"컴파일 중: {sketch_name}")
            compile_process = subprocess.Popen(
                [arduino_cli_path, "compile", "--fqbn", fqbn_mega, sketch_path, "--build-path", build_dir],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            stdout, stderr = compile_process.communicate()
            if compile_process.returncode != 0:
                raise subprocess.CalledProcessError(compile_process.returncode, "compile", stderr)

            print(f"업로드 중: {sketch_name}")
            upload_process = subprocess.Popen(
                [arduino_cli_path, "upload", "-p", port, "--fqbn", fqbn_mega, "--input-file", binary_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            time.sleep(2)
            stdout, stderr = upload_process.communicate()
            if upload_process.returncode != 0:
                raise subprocess.CalledProcessError(upload_process.returncode, "upload", stderr)

        print(f"{sketch_name} 업로드 완료!")
    except subprocess.CalledProcessError as e:
        print(f"오류 발생: {sketch_name} 작업 실패. 오류: {e}")

    total_time = time.time() - start_time
    print(f"{sketch_name} 전체 소요 시간: {total_time:.2f}초")

def monitor_homing_complete(timeout=40):
    """homing.ino가 완료될 때까지 Serial로 모니터링"""
    start_time = time.time()
    try:
        with serial.Serial(port, baud_rate, timeout=1) as ser:
            print("Homing 완료를 기다리는 중...")
            while True:
                if time.time() - start_time > timeout:
                    print("Homing 확인 타임아웃! 루프를 종료합니다.")
                    break

                if ser.in_waiting > 0:
                    line = ser.readline().decode('utf-8').strip()
                    print(line)
                    if "Homing process completed." in line:
                        print("Homing 완료 감지!")
                        break
                time.sleep(0.1)
    except serial.SerialException as e:
        print(f"Serial 연결 실패: {e}")

    print(f"Homing 과정 소요 시간: {time.time() - start_time:.2f}초")

# 첫 번째 파일 업로드 (homing.ino)
compile_and_upload(homing_path, "homing")

# Homing 완료 대기
monitor_homing_complete()

# 두 번째 파일 업로드 (Marlin 펌웨어)
compile_and_upload(marlin_path, "Marlin")
