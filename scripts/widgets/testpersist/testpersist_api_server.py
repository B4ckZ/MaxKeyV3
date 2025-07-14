#!/usr/bin/env python3
"""
MaxLink Test Persist API Server
Serveur Flask pour l'accès aux archives de traçabilité hebdomadaire
Version 3.0 - Avec support CORS complet
"""

import os
import sys
import json
import zipfile
import tempfile
import datetime
from pathlib import Path
from flask import Flask, jsonify, send_file, abort
from werkzeug.serving import make_server
import threading

# Tentative d'import de flask-cors (optionnel)
try:
    from flask_cors import CORS
    CORS_AVAILABLE = True
except ImportError:
    CORS_AVAILABLE = False
    print("Warning: flask-cors non installé, CORS géré manuellement")

# Configuration
STORAGE_DIR = Path("/home/prod/Documents/traçabilité")
ARCHIVES_DIR = STORAGE_DIR / "Archives"
API_PORT = 5001
API_HOST = "0.0.0.0"

# Initialiser Flask
app = Flask(__name__)

# Configuration CORS
if CORS_AVAILABLE:
    CORS(app, resources={
        r"/api/*": {
            "origins": ["*"],
            "methods": ["GET", "POST", "OPTIONS"],
            "allow_headers": ["Content-Type", "Authorization"]
        }
    })
else:
    # CORS manuel si flask-cors non disponible
    @app.after_request
    def after_request(response):
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
        response.headers.add('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
        return response

def get_current_week_info():
    """Retourne l'année et le numéro de semaine courant"""
    now = datetime.datetime.now()
    year, week, weekday = now.isocalendar()
    return year, week

def scan_archives():
    """Scanne le répertoire d'archives et retourne la structure"""
    archives_info = {}
    
    if not ARCHIVES_DIR.exists():
        return archives_info
    
    try:
        # Parcourir les répertoires d'années
        for year_dir in ARCHIVES_DIR.iterdir():
            if year_dir.is_dir() and year_dir.name.isdigit():
                year = year_dir.name
                archives_info[year] = {}
                
                # Chercher les fichiers de semaine dans l'année
                pattern = f"S*_{year}_*.csv"
                weeks_found = set()
                
                for archive_file in year_dir.glob(pattern):
                    filename = archive_file.name
                    try:
                        # Parser: S##_####_machine.csv
                        parts = filename.replace('.csv', '').split('_')
                        if len(parts) >= 3 and parts[0].startswith('S'):
                            week_str = parts[0][1:]
                            week_num = int(week_str)
                            weeks_found.add(week_num)
                    
                    except (ValueError, IndexError):
                        continue
                
                # Organiser par semaines
                for week in sorted(weeks_found, reverse=True):
                    week_key = f"S{week:02d}"
                    archives_info[year][week_key] = {
                        "week_number": week,
                        "files": []
                    }
                    
                    # Lister les fichiers de cette semaine
                    week_pattern = f"S{week:02d}_{year}_*.csv"
                    for file_path in year_dir.glob(week_pattern):
                        file_info = {
                            "filename": file_path.name,
                            "size": file_path.stat().st_size,
                            "modified": file_path.stat().st_mtime
                        }
                        archives_info[year][week_key]["files"].append(file_info)
    
    except Exception as e:
        print(f"Erreur scan archives: {e}")
    
    return archives_info

def get_current_week_files():
    """Retourne les informations sur les fichiers de la semaine courante"""
    current_year, current_week = get_current_week_info()
    
    current_files = {
        "year": current_year,
        "week": current_week,
        "week_label": f"S{current_week:02d}",
        "files": []
    }
    
    # Chercher les fichiers de la semaine courante
    machines = ["509", "511", "RPDT"]
    
    for machine in machines:
        filename = f"S{current_week:02d}_{current_year}_{machine}.csv"
        filepath = STORAGE_DIR / filename
        
        if filepath.exists():
            file_info = {
                "machine": machine,
                "filename": filename,
                "size": filepath.stat().st_size,
                "modified": filepath.stat().st_mtime,
                "path": str(filepath)
            }
            current_files["files"].append(file_info)
    
    return current_files

@app.route('/api/archives', methods=['GET'])
def list_archives():
    """Liste toutes les semaines archivées par année"""
    try:
        archives = scan_archives()
        return jsonify({
            "status": "success",
            "archives": archives,
            "total_years": len(archives)
        })
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route('/api/current', methods=['GET'])
def current_week_info():
    """Informations sur la semaine courante"""
    try:
        current = get_current_week_files()
        return jsonify({
            "status": "success",
            "current_week": current
        })
    except Exception as e:
        return jsonify({
            "status": "error", 
            "message": str(e)
        }), 500

@app.route('/api/download/<int:year>/<int:week>', methods=['GET'])
def download_week_zip(year, week):
    """Télécharge tous les fichiers CSV d'une semaine en ZIP"""
    try:
        # Vérifier que l'année existe dans les archives
        year_dir = ARCHIVES_DIR / str(year)
        if not year_dir.exists():
            abort(404, description=f"Année {year} non trouvée dans les archives")
        
        # Chercher les fichiers de cette semaine
        week_pattern = f"S{week:02d}_{year}_*.csv"
        week_files = list(year_dir.glob(week_pattern))
        
        if not week_files:
            abort(404, description=f"Aucun fichier trouvé pour la semaine {week} de {year}")
        
        # Créer un fichier ZIP temporaire
        with tempfile.NamedTemporaryFile(delete=False, suffix='.zip') as temp_zip:
            with zipfile.ZipFile(temp_zip.name, 'w', zipfile.ZIP_DEFLATED) as zipf:
                for file_path in week_files:
                    # Ajouter le fichier au ZIP avec juste son nom (pas le chemin complet)
                    zipf.write(file_path, file_path.name)
            
            # Nom du fichier ZIP pour le téléchargement
            zip_filename = f"MaxLink_S{week:02d}_{year}_tracabilite.zip"
            
            return send_file(
                temp_zip.name,
                as_attachment=True,
                download_name=zip_filename,
                mimetype='application/zip'
            )
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route('/api/download/current', methods=['GET'])
def download_current_week():
    """Télécharge les fichiers de la semaine courante"""
    try:
        current = get_current_week_files()
        
        if not current["files"]:
            abort(404, description="Aucun fichier trouvé pour la semaine courante")
        
        # Créer un fichier ZIP temporaire
        with tempfile.NamedTemporaryFile(delete=False, suffix='.zip') as temp_zip:
            with zipfile.ZipFile(temp_zip.name, 'w', zipfile.ZIP_DEFLATED) as zipf:
                for file_info in current["files"]:
                    file_path = Path(file_info["path"])
                    if file_path.exists():
                        zipf.write(file_path, file_info["filename"])
            
            # Nom du fichier ZIP
            zip_filename = f"MaxLink_{current['week_label']}_{current['year']}_tracabilite_courante.zip"
            
            return send_file(
                temp_zip.name,
                as_attachment=True,
                download_name=zip_filename,
                mimetype='application/zip'
            )
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route('/api/status', methods=['GET'])
def api_status():
    """Status de l'API et informations système"""
    current_year, current_week = get_current_week_info()
    
    return jsonify({
        "status": "online",
        "service": "MaxLink Test Persist API",
        "version": "3.0.0",
        "cors_enabled": CORS_AVAILABLE,
        "current_week": {
            "year": current_year,
            "week": current_week,
            "label": f"S{current_week:02d}_{current_year}"
        },
        "storage_paths": {
            "base": str(STORAGE_DIR),
            "archives": str(ARCHIVES_DIR)
        },
        "endpoints": [
            "/api/archives",
            "/api/current", 
            "/api/download/<year>/<week>",
            "/api/download/current",
            "/api/status"
        ]
    })

# Gestion des requêtes OPTIONS pour CORS préflight
@app.route('/api/<path:path>', methods=['OPTIONS'])
def handle_options(path):
    """Gère les requêtes OPTIONS CORS"""
    response = jsonify()
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
    return response

class APIServer:
    """Serveur API pour les archives de traçabilité"""
    
    def __init__(self, host=API_HOST, port=API_PORT):
        self.host = host
        self.port = port
        self.server = None
        self.thread = None
    
    def start(self):
        """Démarre le serveur API en arrière-plan"""
        try:
            self.server = make_server(self.host, self.port, app, threaded=True)
            self.thread = threading.Thread(target=self.server.serve_forever)
            self.thread.daemon = True
            self.thread.start()
            print(f"API Server démarré sur http://{self.host}:{self.port}")
            return True
        except Exception as e:
            print(f"Erreur démarrage API Server: {e}")
            return False
    
    def stop(self):
        """Arrête le serveur API"""
        if self.server:
            self.server.shutdown()
            print("API Server arrêté")

def main():
    """Point d'entrée principal pour le serveur API"""
    print("=" * 60)
    print("MaxLink Test Persist API Server v3.0")
    print("=" * 60)
    print(f"Storage: {STORAGE_DIR}")
    print(f"Archives: {ARCHIVES_DIR}")
    print(f"CORS Support: {'Oui (flask-cors)' if CORS_AVAILABLE else 'Oui (manuel)'}")
    print(f"Listening on: http://{API_HOST}:{API_PORT}")
    print("=" * 60)
    
    # Vérifier les répertoires
    if not STORAGE_DIR.exists():
        print(f"ERREUR: Répertoire de stockage non trouvé: {STORAGE_DIR}")
        sys.exit(1)
    
    try:
        # Démarrer le serveur Flask en mode production
        app.run(host=API_HOST, port=API_PORT, debug=False, threaded=True)
    except KeyboardInterrupt:
        print("\nArrêt du serveur API...")
    except Exception as e:
        print(f"Erreur serveur API: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()