import os
import sys
import json
import time
import shutil
import zipfile
import hashlib
import logging
import tempfile
import subprocess
import urllib.request
import urllib.error
import urllib.parse
from pathlib import Path
from datetime import datetime

# --- Config ---
CONFIG_FILE = Path(__file__).parent / "sync-config.json"
DEFAULT_CONFIG = {
    "server_url": "http://100.100.100.100:8080",
    "conera_name": "",
    "check_interval": 300,
    "data_dir": "C:\\Bootdrv\\AlohaQs\\DATA",
    "newdata_dir": "C:\\Bootdrv\\AlohaQs\\NEWDATA",
    "iberqs_path": "C:\\BootDrv\\AlohaQS\\BIN\\IBERQS.exe",
    "version_file": "C:\\Bootdrv\\AlohaQs\\version.txt",
    "log_file": "C:\\Bootdrv\\AlohaQs\\sync-log.txt",
    "force_applied_file": "C:\\Bootdrv\\AlohaQs\\force-applied.txt",
    "retry_attempts": 5,
    "retry_delay": 30,
}

config = None

# --- Logging ---
def setup_logging():
    log_file = config.get("log_file", str(Path(__file__).parent / "sync-log.txt"))
    try:
        logging.basicConfig(
            filename=log_file,
            level=logging.INFO,
            format="%(asctime)s [%(levelname)s] %(message)s",
        )
    except Exception:
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s [%(levelname)s] %(message)s",
        )

def log(msg, level="info"):
    if level == "info":
        logging.info(msg)
    elif level == "error":
        logging.error(msg)
    elif level == "warning":
        logging.warning(msg)

def log_error(msg):
    logging.error(msg)

# --- Config ---
def load_config():
    global config
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r") as f:
                config = json.load(f)
            for k, v in DEFAULT_CONFIG.items():
                if k not in config:
                    config[k] = v
            return True
        except Exception as e:
            log_error(f"Error al cargar config: {e}")

    config = dict(DEFAULT_CONFIG)
    config["conera_name"] = os.environ.get("COMPUTERNAME", "CONERA-" + datetime.now().strftime("%Y%m%d"))
    save_config()
    log("Configuracion por defecto creada. EDITALA antes de ejecutar.", "warning")
    return False

def save_config():
    try:
        with open(CONFIG_FILE, "w") as f:
            json.dump(config, f, indent=4)
    except Exception as e:
        log_error(f"Error al guardar config: {e}")

# --- Version ---
def read_local_version():
    vf = config.get("version_file")
    if not vf:
        return ""
    try:
        if os.path.exists(vf):
            with open(vf, "r") as f:
                return f.read().strip()
    except Exception:
        pass
    return ""

def write_local_version(version):
    vf = config.get("version_file")
    if not vf:
        return
    try:
        os.makedirs(os.path.dirname(vf), exist_ok=True)
        with open(vf, "w") as f:
            f.write(version)
    except Exception as e:
        log_error(f"Error al escribir version: {e}")

# --- HTTP ---
def http_get(url, timeout=30):
    last_error = None
    attempts = config.get("retry_attempts", 5)
    delay = config.get("retry_delay", 30)
    for attempt in range(1, attempts + 1):
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except Exception as e:
            last_error = e
            if attempt < attempts:
                time.sleep(delay)
    raise last_error

def http_get_json(url, timeout=30):
    data = http_get(url, timeout)
    return json.loads(data.decode("utf-8"))

def http_download(url, dest_path, timeout=120):
    for attempt in range(1, config.get("retry_attempts", 3) + 1):
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                with open(dest_path, "wb") as f:
                    while True:
                        chunk = resp.read(8192)
                        if not chunk:
                            break
                        f.write(chunk)
                return True
        except Exception as e:
            log_error(f"Descarga intento {attempt} fallo: {e}")
            if attempt < config.get("retry_attempts", 3):
                time.sleep(config.get("retry_delay", 30))
    return False

# --- File ops ---
def safe_copy(src, dst):
    try:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        return True
    except Exception as e:
        log_error(f"Error copiando {src}: {e}")
        return False

def install_update(zip_path):
    data_dir = config.get("data_dir", "")
    newdata_dir = config.get("newdata_dir", "")
    if not data_dir or not newdata_dir:
        log_error("data_dir y newdata_dir no configurados")
        return False

    extract_dir = tempfile.mkdtemp(prefix="dbf_sync_")
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(extract_dir)
        dbf_files = [f for f in os.listdir(extract_dir) if f.lower().endswith(".dbf")]
        copied = 0
        for f in dbf_files:
            src = os.path.join(extract_dir, f)
            if safe_copy(src, os.path.join(data_dir, f)) & safe_copy(src, os.path.join(newdata_dir, f)):
                copied += 1
        log(f"Copiados {copied} archivos a DATA y NEWDATA")
        return copied > 0
    except Exception as e:
        log_error(f"Error durante instalacion: {e}")
        return False
    finally:
        shutil.rmtree(extract_dir, ignore_errors=True)

def read_force_applied():
    faf = config.get("force_applied_file", "")
    if not faf:
        return ""
    try:
        if os.path.exists(faf):
            with open(faf, "r") as f:
                return f.read().strip()
    except Exception:
        pass
    return ""

def write_force_applied(version):
    faf = config.get("force_applied_file", "")
    if not faf:
        return
    try:
        os.makedirs(os.path.dirname(faf), exist_ok=True)
        with open(faf, "w") as f:
            f.write(version)
    except Exception as e:
        log_error(f"Error al escribir force-applied: {e}")

def run_action(action):
    log(f"Ejecutando accion: {action}")
    if action == "restart":
        iberqs = config.get("iberqs_path", "")
        if iberqs and os.path.exists(iberqs):
            subprocess.run(["taskkill", "/f", "/im", "IBERQS.exe"], capture_output=True)
            time.sleep(2)
            subprocess.Popen([iberqs])
            log("IBERQS reiniciado")
        else:
            log_error(f"IBERQS no encontrado en: {iberqs}")
    elif action == "logoff":
        os.system("shutdown /l /f")
        log("Cerrando sesion...")

# --- Force update check ---
def check_force_update(server_url, conera_name=""):
    try:
        url = f"{server_url}/api/force-update-status?conera_name={urllib.parse.quote(conera_name)}"
        data = http_get_json(url, timeout=15)
        if data.get("active"):
            log(f"Orden forzada: version={data.get('version')} action={data.get('action')}")
            return data.get("version"), data.get("action")
        return None, None
    except Exception as e:
        return None, None

def acknowledge_force_update(server_url, conera_name, status="true"):
    try:
        data = json.dumps({"name": conera_name, "status": status}).encode()
        req = urllib.request.Request(
            f"{server_url}/api/force-update-ack",
            data=data,
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(req, timeout=10)
    except Exception:
        pass

# --- Sync ---
def sync():
    server_url = config.get("server_url", "").rstrip("/")
    conera_name = config.get("conera_name", os.environ.get("COMPUTERNAME", "DESCONOCIDA"))

    if not server_url:
        log_error("server_url no configurado")
        return

    # Check force update first
    force_version, force_action = check_force_update(server_url, conera_name)
    if force_version:
        force_applied = read_force_applied()
        if force_applied == force_version:
            return
        log(f"Aplicando actualizacion forzada: {force_version}")
        tmp_zip = os.path.join(tempfile.gettempdir(), f"dbf_sync_force_{force_version}.zip")
        try:
            if http_download(f"{server_url}/api/download", tmp_zip):
                success = install_update(tmp_zip)
                if success:
                    write_local_version(force_version)
                    write_force_applied(force_version)
                    log(f"Actualizacion forzada completada: {force_version}")
                    run_action(force_action)
                    acknowledge_force_update(server_url, conera_name)
        finally:
            try:
                if os.path.exists(tmp_zip):
                    os.remove(tmp_zip)
            except Exception:
                pass
        return

    # Normal sync
    try:
        version_info = http_get_json(f"{server_url}/api/version", timeout=15)
        server_version = version_info.get("version", "")
        if not server_version or server_version == "ninguna":
            return
    except Exception as e:
        return

    local_version = read_local_version()
    if local_version == server_version:
        check_in(server_url, conera_name, local_version)
        return

    log(f"Actualizacion normal: {server_version}")
    tmp_zip = os.path.join(tempfile.gettempdir(), f"dbf_sync_{server_version}.zip")
    try:
        if http_download(f"{server_url}/api/download", tmp_zip):
            success = install_update(tmp_zip)
            if success:
                write_local_version(server_version)
                log(f"Actualizacion completada: {server_version}")
                check_in(server_url, conera_name, server_version)
    finally:
        try:
            if os.path.exists(tmp_zip):
                os.remove(tmp_zip)
        except Exception:
            pass

def check_in(server_url, conera_name, version):
    try:
        data = json.dumps({"name": conera_name, "version": version}).encode()
        req = urllib.request.Request(
            f"{server_url}/api/conera/checkin",
            data=data,
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(req, timeout=15)
    except Exception:
        pass

def register(server_url, conera_name):
    try:
        data = json.dumps({"name": conera_name}).encode()
        req = urllib.request.Request(
            f"{server_url}/api/conera/register",
            data=data,
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(req, timeout=15)
    except Exception as e:
        log_error(f"Error al registrar: {e}")

def main_loop():
    server_url = config.get("server_url", "").rstrip("/")
    conera_name = config.get("conera_name", os.environ.get("COMPUTERNAME", "DESCONOCIDA"))
    interval = config.get("check_interval", 300)

    log("=" * 40)
    log(f"DBF Sync Client iniciado - {conera_name}")
    log(f"Servidor: {server_url}")
    log(f"DATA: {config.get('data_dir')}")
    log(f"NEWDATA: {config.get('newdata_dir')}")
    log(f"Intervalo: {interval}s")
    log("=" * 40)

    register(server_url, conera_name)

    while True:
        try:
            sync()
        except Exception as e:
            log_error(f"Error en ciclo: {e}")
        time.sleep(interval)

if __name__ == "__main__":
    if not load_config():
        sys.exit(1)
    setup_logging()
    try:
        main_loop()
    except KeyboardInterrupt:
        log("Cliente detenido")
