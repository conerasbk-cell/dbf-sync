import os
import json
import time
import shutil
import hashlib
import zipfile
import sqlite3
import logging
from datetime import datetime
from threading import Thread
from pathlib import Path

from flask import Flask, jsonify, send_file, request, render_template

BASE_DIR = Path(__file__).parent.absolute()
DB_UPLOADS_DIR = BASE_DIR / "db_uploads"
VERSIONS_DIR = BASE_DIR / "versions"
LOGS_DIR = BASE_DIR / "logs"
DB_PATH = BASE_DIR / "sync.db"

app = Flask(__name__)

# --- Ensure directories exist ---
LOGS_DIR.mkdir(parents=True, exist_ok=True)
DB_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
VERSIONS_DIR.mkdir(parents=True, exist_ok=True)

# --- Logging setup ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOGS_DIR / "server.log"),
        logging.StreamHandler(),
    ],
)

# --- DB init ---
def init_db():
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            version TEXT NOT NULL,
            created_at TEXT NOT NULL,
            file_count INTEGER DEFAULT 0,
            total_size INTEGER DEFAULT 0,
            checksum TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS coneras (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            ip TEXT,
            zone TEXT DEFAULT '',
            last_checkin TEXT,
            current_version TEXT,
            status TEXT DEFAULT 'pendiente'
        )
    """)
    try:
        c.execute("ALTER TABLE coneras ADD COLUMN zone TEXT DEFAULT ''")
    except Exception:
        pass
    c.execute("""
        CREATE TABLE IF NOT EXISTS force_update (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            version TEXT NOT NULL,
            action TEXT DEFAULT 'none',
            created_at TEXT NOT NULL,
            acks TEXT DEFAULT '[]'
        )
    """)
    conn.commit()
    conn.close()

init_db()

# --- Helpers ---
def get_current_version():
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("SELECT version, created_at, file_count, total_size, checksum FROM versions ORDER BY id DESC LIMIT 1")
    row = c.fetchone()
    conn.close()
    if row:
        return {
            "version": row[0],
            "created_at": row[1],
            "file_count": row[2],
            "total_size": row[3],
            "checksum": row[4]
        }
    return None

def compute_checksum(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            h.update(chunk)
    return h.hexdigest()

def create_version_from_uploads():
    files = [f for f in DB_UPLOADS_DIR.iterdir() if f.suffix.lower() == ".dbf"]
    if not files:
        return None

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    version_name = f"v{timestamp}"
    zip_name = f"{version_name}.zip"
    zip_path = VERSIONS_DIR / zip_name

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in files:
            zf.write(f, f.name)

    total_size = sum(f.stat().st_size for f in files)
    checksum = compute_checksum(zip_path)

    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute(
        "INSERT INTO versions (version, created_at, file_count, total_size, checksum) VALUES (?, ?, ?, ?, ?)",
        (version_name, datetime.now().isoformat(), len(files), total_size, checksum),
    )
    conn.commit()
    conn.close()

    return {
        "version": version_name,
        "created_at": datetime.now().isoformat(),
        "file_count": len(files),
        "total_size": total_size,
        "checksum": checksum,
        "zip_path": str(zip_path),
    }

def get_coneras_list():
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("SELECT name, ip, zone, last_checkin, current_version, status FROM coneras ORDER BY zone, name")
    rows = c.fetchall()
    conn.close()
    ten_min_ago = datetime.now().isoformat(timespec="seconds")[:19]
    result = []
    for r in rows:
        online = bool(r[3]) and r[3][:19] >= ten_min_ago
        result.append({
            "name": r[0], "ip": r[1], "zone": r[2],
            "last_checkin": r[3], "current_version": r[4], "status": r[5],
            "online": online,
        })
    return result

def register_conera(name, ip, version, zone=""):
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("SELECT id FROM coneras WHERE name = ?", (name,))
    row = c.fetchone()
    now = datetime.now().isoformat()
    if row:
        c.execute(
            "UPDATE coneras SET ip = ?, last_checkin = ?, current_version = ?, status = ? WHERE id = ?",
            (ip, now, version, "actualizada", row[0]),
        )
    else:
        c.execute(
            "INSERT INTO coneras (name, ip, zone, last_checkin, current_version, status) VALUES (?, ?, ?, ?, ?, ?)",
            (name, ip, zone, now, version, "actualizada"),
        )
    conn.commit()
    conn.close()

# --- Routes ---
@app.route("/")
def index():
    version = get_current_version()
    coneras = get_coneras_list()
    return render_template("panel.html", version=version, coneras=coneras)

@app.route("/api/version")
def api_version():
    v = get_current_version()
    if v:
        return jsonify(v)
    return jsonify({"version": "ninguna", "created_at": "", "file_count": 0, "total_size": 0})

@app.route("/api/versions")
def api_versions():
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("SELECT version, created_at, file_count, total_size, checksum FROM versions ORDER BY id DESC LIMIT 50")
    rows = c.fetchall()
    conn.close()
    return jsonify([
        {
            "version": r[0],
            "created_at": r[1],
            "file_count": r[2],
            "total_size": r[3],
            "checksum": r[4],
        }
        for r in rows
    ])

@app.route("/api/conera/checkin-log")
def api_conera_checkin_log():
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("SELECT name, last_checkin, current_version, zone FROM coneras WHERE last_checkin IS NOT NULL ORDER BY last_checkin DESC LIMIT 50")
    rows = c.fetchall()
    conn.close()
    return jsonify([
        {"name": r[0], "time": r[1], "version": r[2], "zone": r[3]}
        for r in rows
    ])

@app.route("/api/download")
def api_download():
    v = get_current_version()
    if not v:
        return jsonify({"error": "No hay version disponible"}), 404
    zip_path = VERSIONS_DIR / f"{v['version']}.zip"
    if not zip_path.exists():
        return jsonify({"error": "Archivo no encontrado"}), 404
    return send_file(str(zip_path), as_attachment=True, download_name=f"{v['version']}.zip")

@app.route("/api/coneras")
def api_coneras():
    return jsonify(get_coneras_list())

@app.route("/api/create-version", methods=["POST"])
def api_create_version():
    files = list(DB_UPLOADS_DIR.glob("*.dbf"))
    if not files:
        return jsonify({"error": "No hay archivos .dbf en db_uploads/"}), 400

    result = create_version_from_uploads()
    if result:
        logging.info(f"Version creada: {result['version']} ({result['file_count']} archivos)")
        return jsonify({"success": True, "version": result})
    return jsonify({"error": "Error al crear version"}), 500

@app.route("/api/conera/checkin", methods=["POST"])
def api_conera_checkin():
    data = request.json
    name = data.get("name", "desconocida")
    ip = request.remote_addr or data.get("ip", "")
    version = data.get("version", "")
    zone = data.get("zone", "")
    register_conera(name, ip, version, zone)
    return jsonify({"success": True})

@app.route("/api/conera/register", methods=["POST"])
def api_conera_register():
    data = request.json
    name = data.get("name", "desconocida")
    ip = request.remote_addr or data.get("ip", "")
    zone = data.get("zone", "")
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("SELECT id FROM coneras WHERE name = ?", (name,))
    if not c.fetchone():
        c.execute(
            "INSERT INTO coneras (name, ip, zone, last_checkin, current_version, status) VALUES (?, ?, ?, ?, ?, ?)",
            (name, ip, zone, datetime.now().isoformat(), "", "pendiente"),
        )
        conn.commit()
        logging.info(f"Nueva conera registrada: {name} ({ip}) zona={zone}")
    conn.close()
    return jsonify({"success": True})

@app.route("/api/conera/update-zone", methods=["POST"])
def api_conera_update_zone():
    data = request.json
    name = data.get("name", "")
    zone = data.get("zone", "")
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("UPDATE coneras SET zone = ? WHERE name = ?", (zone, name))
    conn.commit()
    conn.close()
    logging.info(f"Zona actualizada: {name} -> {zone}")
    return jsonify({"success": True})

@app.route("/api/force-update", methods=["POST"])
def api_force_update():
    data = request.json
    action = data.get("action", "none")
    selected = data.get("coneras", [])
    v = get_current_version()
    if not v:
        return jsonify({"error": "No hay version disponible"}), 400
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("DELETE FROM force_update")
    c.execute(
        "INSERT INTO force_update (version, action, created_at, acks) VALUES (?, ?, ?, ?)",
        (v["version"], action, datetime.now().isoformat(), json.dumps([])),
    )
    conn.commit()
    conn.close()
    logging.info(f"Actualizacion forzada: version={v['version']}, action={action}, coneras={len(selected)}")
    return jsonify({"success": True, "version": v["version"], "action": action})

@app.route("/api/force-update-status")
def api_force_update_status():
    conera_name = request.args.get("conera_name", "")
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("SELECT version, action, created_at, acks FROM force_update ORDER BY id DESC LIMIT 1")
    row = c.fetchone()
    conn.close()
    if row:
        acks = json.loads(row[3]) if row[3] else []
        v = get_current_version()
        already_acked = any(a.get("name") == conera_name for a in acks) if conera_name else False
        return jsonify({
            "active": not already_acked,
            "version": row[0],
            "action": row[1],
            "created_at": row[2],
            "acks": acks,
            "ack_count": len(acks),
            "current_version": v["version"] if v else "",
        })
    return jsonify({"active": False})

@app.route("/api/force-update-ack", methods=["POST"])
def api_force_update_ack():
    data = request.json
    name = data.get("name", "")
    status = data.get("status", "false")
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("SELECT acks FROM force_update ORDER BY id DESC LIMIT 1")
    row = c.fetchone()
    if row:
        acks = json.loads(row[0]) if row[0] else []
        acks.append({"name": name, "status": status, "time": datetime.now().isoformat()})
        c.execute("UPDATE force_update SET acks = ?", (json.dumps(acks),))
        conn.commit()
    conn.close()
    return jsonify({"success": True})

@app.route("/api/force-update-results")
def api_force_update_results():
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("SELECT version, action, created_at, acks FROM force_update ORDER BY id DESC LIMIT 1")
    row = c.fetchone()
    conn.close()
    if not row:
        return jsonify({"has_results": False})
    acks = json.loads(row[3]) if row[3] else []
    # List all coneras with their ack status
    all_coneras = get_coneras_list()
    results = []
    for conera in all_coneras:
        ack = [a for a in acks if a["name"] == conera["name"]]
        results.append({
            "name": conera["name"],
            "zone": conera.get("zone", ""),
            "status": conera["status"],
            "acknowledged": len(ack) > 0,
            "ack_time": ack[0]["time"] if ack else None,
            "ack_status": ack[0]["status"] if ack else None,
        })
    return jsonify({
        "has_results": True,
        "version": row[0],
        "action": row[1],
        "created_at": row[2],
        "ack_count": len(acks),
        "total": len(all_coneras),
        "results": results,
    })

@app.route("/api/upload", methods=["POST"])
def api_upload():
    if "files" not in request.files:
        return jsonify({"error": "No se enviaron archivos"}), 400
    files = request.files.getlist("files")
    uploaded = 0
    for f in files:
        if f.filename.lower().endswith(".dbf"):
            safe_name = f.filename[:-4] + ".dbf"
            f.save(str(DB_UPLOADS_DIR / safe_name))
            uploaded += 1
    if uploaded > 0:
        logging.info(f"Subidos {uploaded} archivos via web")
        return jsonify({"success": True, "uploaded": uploaded})
    return jsonify({"error": "No se subieron archivos .dbf"}), 400

if __name__ == "__main__":
    DB_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    VERSIONS_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)

    port = int(os.environ.get("PORT", 8080))
    print("=" * 50)
    print("  DBF SYNC SERVER v1.0")
    print(f"  Puerto: {port}")
    print("=" * 50)
    print()
    app.run(host="0.0.0.0", port=port, debug=False)
