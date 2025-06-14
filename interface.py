import tkinter as tk
from tkinter import scrolledtext, messagebox
import subprocess
import os
import sys
import threading
import time
from datetime import datetime
import re
import logging
from pathlib import Path
import json

# ===============================================================================
# CONFIGURATION DU LOGGING
# ===============================================================================

base_dir = Path(__file__).resolve().parent
log_dir = base_dir / "logs" / "python"
log_dir.mkdir(parents=True, exist_ok=True)

script_name = "interface"
log_file = log_dir / f"{script_name}.log"

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] [interface] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.FileHandler(log_file, mode='a', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('interface')

# ===============================================================================
# CONFIGURATION
# ===============================================================================

# Couleurs du thème Nord
COLORS = {
    "nord0": "#2E3440",  # Fond sombre
    "nord1": "#3B4252",  # Fond moins sombre
    "nord3": "#4C566A",  # Bordure sélection
    "nord4": "#D8DEE9",  # Texte tertiaire
    "nord6": "#ECEFF4",  # Texte
    "nord8": "#88C0D0",  # Accent primaire
    "nord10": "#5E81AC", # Bouton Installer
    "nord11": "#BF616A", # Rouge
    "nord12": "#D08770", # Orange
    "nord14": "#A3BE8C", # Vert / Succès
    "nord15": "#B48EAD", # Violet
}

# ===============================================================================
# GESTIONNAIRE DE STATUTS SIMPLIFIÉ
# ===============================================================================

class StatusManager:
    """Gestionnaire unifié pour tous les statuts - VERSION SIMPLIFIÉE"""
    
    def __init__(self):
        self.status_file = Path("/var/lib/maxlink/services_status.json")
        
        # Créer le répertoire si nécessaire
        self.status_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Statuts par défaut
        self.default_statuses = {
            'full_install': {'status': 'active', 'is_meta': True},
            'update': {'status': 'inactive'},
            'ap': {'status': 'inactive'},
            'nginx': {'status': 'inactive'},
            'mqtt': {'status': 'inactive'},
            'mqtt_wgs': {'status': 'inactive'},
            'orchestrator': {'status': 'inactive'}
        }
    
    def load_statuses(self):
        """Charge les statuts depuis le fichier - TOUJOURS relire le fichier"""
        # Si le fichier existe, lire directement depuis le fichier
        if self.status_file.exists():
            try:
                with open(self.status_file, 'r') as f:
                    saved_statuses = json.load(f)
                
                # Construire le dictionnaire des statuts
                statuses = {}
                for service_id, info in saved_statuses.items():
                    statuses[service_id] = {
                        'status': info.get('status', 'inactive'),
                        'last_update': info.get('last_update', '')
                    }
                
                # Ajouter full_install s'il n'est pas dans le fichier
                if 'full_install' not in statuses:
                    statuses['full_install'] = {'status': 'active', 'is_meta': True}
                    
                return statuses
                        
            except Exception as e:
                logger.error(f"Erreur chargement statuts: {e}")
                # En cas d'erreur, retourner les valeurs par défaut
                return self.default_statuses.copy()
        else:
            # Si le fichier n'existe pas, retourner les valeurs par défaut
            return self.default_statuses.copy()
    
    def get_status(self, service_id):
        """Retourne le statut actuel d'un service - RELIRE LE FICHIER"""
        statuses = self.load_statuses()
        return statuses.get(service_id, {}).get('status', 'inactive')
    
    def is_active(self, service_id):
        """Vérifie si un service est actif - RELIRE LE FICHIER"""
        return self.get_status(service_id) == 'active'

# ===============================================================================
# GESTIONNAIRE DE VARIABLES
# ===============================================================================

class VariablesManager:
    """Gestionnaire pour charger les variables depuis variables.sh"""
    
    def __init__(self, base_path):
        self.base_path = base_path
        self.variables = {}
        self.load_variables()
    
    def load_variables(self):
        """Charge les variables depuis variables.sh"""
        variables_file = os.path.join(self.base_path, "scripts", "common", "variables.sh")
        
        if not os.path.exists(variables_file):
            raise FileNotFoundError(f"Fichier variables.sh non trouvé: {variables_file}")
        
        try:
            with open(variables_file, 'r') as f:
                content = f.read()
            
            # Parser les variables simples
            for line in content.split('\n'):
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    if line.startswith('export') or line.startswith('function') or '()' in line:
                        continue
                    
                    match = re.match(r'^([A-Z_][A-Z0-9_]*)="?([^"]*)"?$', line)
                    if match:
                        key = match.group(1)
                        value = match.group(2)
                        self.variables[key] = value
            
            # Valeurs par défaut
            if 'SERVICES_STATUS_FILE' not in self.variables:
                self.variables['SERVICES_STATUS_FILE'] = '/var/lib/maxlink/services_status.json'
            
            # Services disponibles (ordre fixe)
            self.services = [
                {"id": "full_install", "name": "One-click install", "is_meta": True},
                {"id": "update", "name": "Update RPI"},
                {"id": "ap", "name": "Network AP"},
                {"id": "nginx", "name": "NginX Web"},
                {"id": "mqtt", "name": "MQTT BKR"},
                {"id": "mqtt_wgs", "name": "MQTT WGS"},
                {"id": "orchestrator", "name": "Finalisation"}
            ]
            
            logger.info(f"Variables chargées: {len(self.variables)} variables")
                
        except Exception as e:
            logger.error(f"Erreur lors du chargement de variables.sh: {e}")
            raise
    
    def get(self, key, default=None):
        return self.variables.get(key, default)
    
    def get_window_title(self):
        version = self.get('MAXLINK_VERSION', '1.0')
        copyright_text = self.get('MAXLINK_COPYRIGHT', '© 2025 WERIT')
        return f"MaxLink™ Admin Panel V{version} - {copyright_text}"
    
    def get_services_list(self):
        return self.services

# ===============================================================================
# APPLICATION PRINCIPALE SIMPLIFIÉE
# ===============================================================================

class MaxLinkApp:
    def __init__(self, root, variables):
        self.root = root
        self.variables = variables
        
        logger.info("Initialisation de l'application MaxLink")
        
        self.base_path = os.path.dirname(os.path.abspath(__file__))
        
        # Configuration de la fenêtre
        self.root.title(self.variables.get_window_title())
        self.root.geometry("1200x750")
        self.root.configure(bg=COLORS["nord0"])
        
        self.center_window()
        
        # Vérifier les privilèges root
        self.root_mode = self.check_root_mode()
        logger.info(f"Mode root: {self.root_mode}")
        
        # Gestionnaire de statuts unifié
        self.status_manager = StatusManager()
        
        # Services disponibles
        self.services = self.variables.get_services_list()
        self.selected_service = self.services[0] if self.services else None
        
        logger.info(f"Services chargés: {len(self.services)}")
        
        self.progress_value = 0
        self.progress_max = 100
        
        self.current_process = None
        self.current_thread = None
        
        self.create_interface()
        
        # Mettre à jour immédiatement les indicateurs visuels
        self.update_all_indicators()
        
        # Vérification périodique
        self.periodic_refresh()
    
    def refresh_all_statuses(self):
        """Recharge tous les statuts et met à jour l'interface - SIMPLIFIÉ"""
        # Les statuts sont toujours relus depuis le fichier par le StatusManager
        # On met juste à jour l'interface
        self.update_all_indicators()
        logger.debug("Rafraîchissement des indicateurs effectué")
    
    def periodic_refresh(self):
        """Rafraîchissement périodique simple"""
        # Ne rafraîchir que si aucune installation en cours
        if self.current_thread is None:
            self.refresh_all_statuses()
        # Répéter toutes les 2 secondes (plus réactif)
        self.root.after(2000, self.periodic_refresh)
    
    def update_all_indicators(self):
        """Met à jour tous les indicateurs visuels - LECTURE DIRECTE DU FICHIER"""
        # Toujours relire le fichier pour avoir l'état le plus récent
        current_statuses = self.status_manager.load_statuses()
        
        for service in self.services:
            if "indicator" in service:
                # Lire le statut actuel depuis les données rechargées
                is_active = current_statuses.get(service['id'], {}).get('status', 'inactive') == 'active'
                
                # Mettre à jour seulement si le statut a changé
                current_color = COLORS["nord14"] if is_active else COLORS["nord11"]
                
                # Effacer et redessiner l'indicateur
                service["indicator"].delete("all")
                service["indicator"].create_oval(2, 2, 18, 18, fill=current_color, outline="")
                
                logger.debug(f"Indicateur mis à jour pour {service['id']}: {'vert' if is_active else 'rouge'}")
    
    def check_root_mode(self):
        """Vérifier si l'interface est lancée avec les privilèges root"""
        try:
            # Sur Linux/Unix
            if hasattr(os, 'geteuid'):
                return os.geteuid() == 0
            # Sur Windows
            elif os.name == 'nt':
                import ctypes
                return ctypes.windll.shell32.IsUserAnAdmin() != 0
            else:
                return False
        except:
            return False
    
    def center_window(self):
        """Centre la fenêtre sur l'écran"""
        self.root.update_idletasks()
        width = self.root.winfo_width()
        height = self.root.winfo_height()
        x = (self.root.winfo_screenwidth() // 2) - (width // 2)
        y = (self.root.winfo_screenheight() // 2) - (height // 2)
        self.root.geometry(f'{width}x{height}+{x}+{y}')
    
    def create_interface(self):
        main = tk.Frame(self.root, bg=COLORS["nord0"], padx=20, pady=20)
        main.pack(fill="both", expand=True)
        
        # Panneau gauche (services + bouton)
        self.left_frame = tk.Frame(main, bg=COLORS["nord1"], width=300)
        self.left_frame.pack_propagate(False)
        self.left_frame.pack(side="left", fill="both", padx=(0, 20))
        
        # Zone des services
        services_frame = tk.Frame(self.left_frame, bg=COLORS["nord1"], padx=20, pady=20)
        services_frame.pack(fill="both", expand=True)
        
        services_title = tk.Label(
            services_frame,
            text="Services Disponibles",
            font=("Arial", 18, "bold"),
            bg=COLORS["nord1"],
            fg=COLORS["nord6"]
        )
        services_title.pack(pady=(0, 20))
        
        # Créer les services
        for service in self.services:
            self.create_service_item(services_frame, service)
        
        # Zone du bouton
        buttons_frame = tk.Frame(self.left_frame, bg=COLORS["nord1"], padx=20, pady=20)
        buttons_frame.pack(fill="x")
        
        self.create_action_buttons(buttons_frame)
        
        # Panneau droit (console)
        right_frame = tk.Frame(main, bg=COLORS["nord1"])
        right_frame.pack(side="right", fill="both", expand=True)
        
        # Console
        console_frame = tk.Frame(right_frame, bg=COLORS["nord1"], padx=20, pady=20)
        console_frame.pack(fill="both", expand=True)
        
        console_title_frame = tk.Frame(console_frame, bg=COLORS["nord1"])
        console_title_frame.pack(fill="x", pady=(0, 10))
        
        console_title = tk.Label(
            console_title_frame,
            text="Console de Sortie",
            font=("Arial", 18, "bold"),
            bg=COLORS["nord1"],
            fg=COLORS["nord6"]
        )
        console_title.pack(side="left")
        
        privilege_text = "Mode Privilégié: ACTIF" if self.root_mode else "Mode Privilégié: INACTIF"
        privilege_color = COLORS["nord14"] if self.root_mode else COLORS["nord11"]
        
        privilege_label = tk.Label(
            console_title_frame,
            text=privilege_text,
            font=("Arial", 12, "bold"),
            bg=COLORS["nord1"],
            fg=privilege_color
        )
        privilege_label.pack(side="right")
        
        self.console = scrolledtext.ScrolledText(
            console_frame, 
            bg=COLORS["nord0"], 
            fg=COLORS["nord6"],
            font=("Consolas", 11),
            wrap=tk.WORD
        )
        self.console.pack(fill="both", expand=True)
        
        self.create_progress_bar(right_frame)
        
        self.console.insert(tk.END, f"Console prête - {privilege_text}\n\n")
        self.console.config(state=tk.DISABLED)
        
        self.update_selection()
    
    def create_progress_bar(self, parent):
        """Crée la barre de progression"""
        self.progress_frame = tk.Frame(parent, bg=COLORS["nord1"], padx=20, pady=20)
        self.progress_frame.pack(fill="x", side="bottom")
        
        self.progress_canvas = tk.Canvas(
            self.progress_frame,
            height=30,
            bg=COLORS["nord0"],
            highlightthickness=0
        )
        self.progress_canvas.pack(fill="x")
        
        self.progress_frame.pack_forget()
    
    def create_service_item(self, parent, service):
        """Crée un élément de service"""
        frame = tk.Frame(
            parent,
            bg=COLORS["nord1"],
            highlightthickness=3,
            padx=15,
            pady=10
        )
        frame.pack(fill="x", pady=10)
        
        frame.bind("<Button-1>", lambda e, s=service: self.select_service(s))
        
        # Nom du service
        label = tk.Label(
            frame, 
            text=service["name"],
            font=("Arial", 14, "bold"),
            bg=COLORS["nord1"],
            fg=COLORS["nord6"]
        )
        label.pack(side="left", fill="both", expand=True)
        
        # Indicateur de statut - lire directement depuis le fichier
        is_active = self.status_manager.is_active(service['id'])
        status_color = COLORS["nord14"] if is_active else COLORS["nord11"]
        
        indicator = tk.Canvas(frame, width=20, height=20, bg=COLORS["nord1"], highlightthickness=0)
        indicator.pack(side="right", padx=10)
        indicator.create_oval(2, 2, 18, 18, fill=status_color, outline="")
        
        service["frame"] = frame
        service["indicator"] = indicator
    
    def create_action_buttons(self, parent):
        """Crée le bouton d'action"""
        button_style = {
            "font": ("Arial", 16, "bold"),
            "width": 20,
            "height": 2,
            "borderwidth": 0,
            "highlightthickness": 0,
            "cursor": "hand2"
        }
        
        btn = tk.Button(
            parent, 
            text="Installer",
            bg=COLORS["nord10"],
            fg=COLORS["nord6"],
            command=lambda: self.run_action("install"),
            **button_style
        )
        btn.pack(fill="x", pady=8)
    
    def select_service(self, service):
        """Sélectionne un service"""
        if self.selected_service == service:
            return
            
        old_selected = self.selected_service
        self.selected_service = service
        
        self.update_selection_optimized(old_selected, service)
        
        if hasattr(self, '_last_log_time'):
            if time.time() - self._last_log_time > 0.5:
                logger.debug(f"Service sélectionné: {service['name']}")
                self._last_log_time = time.time()
        else:
            self._last_log_time = time.time()
    
    def update_selection(self):
        """Met à jour l'affichage de la sélection"""
        for service in self.services:
            is_selected = service == self.selected_service
            border_color = COLORS["nord8"] if is_selected else COLORS["nord1"]
            service["frame"].config(highlightbackground=border_color, highlightcolor=border_color)
    
    def update_selection_optimized(self, old_service, new_service):
        """Met à jour seulement les services qui changent"""
        if old_service and "frame" in old_service:
            old_service["frame"].config(
                highlightbackground=COLORS["nord1"], 
                highlightcolor=COLORS["nord1"]
            )
        
        if new_service and "frame" in new_service:
            new_service["frame"].config(
                highlightbackground=COLORS["nord8"], 
                highlightcolor=COLORS["nord8"]
            )
    
    def show_progress_bar(self):
        """Affiche la barre de progression"""
        self.progress_frame.pack(fill="x", side="bottom")
        self.progress_value = 0
        self.update_progress_bar()
    
    def hide_progress_bar(self):
        """Masque la barre de progression"""
        self.progress_frame.pack_forget()
    
    def update_progress_bar(self, value=None):
        """Met à jour la barre de progression"""
        if value is not None:
            self.progress_value = value
        
        self.progress_canvas.update_idletasks()
        width = self.progress_canvas.winfo_width() - 20
        height = 20
        
        self.progress_canvas.delete("all")
        
        # Fond
        self.progress_canvas.create_rectangle(
            10, 5, width + 10, height + 5,
            fill=COLORS["nord3"], outline=""
        )
        
        # Barre de progression
        if self.progress_value > 0:
            filled_width = int(width * self.progress_value / self.progress_max)
            self.progress_canvas.create_rectangle(
                10, 5, filled_width + 10, height + 5,
                fill=COLORS["nord8"], outline=""
            )
        
        # Pourcentage
        percentage = int(self.progress_value * 100 / self.progress_max)
        self.progress_canvas.create_text(
            width / 2 + 10, height / 2 + 5,
            text=f"{percentage}%",
            fill=COLORS["nord6"],
            font=("Arial", 10, "bold")
        )
    
    def run_action(self, action):
        """Exécute une action sur le service sélectionné"""
        if not self.selected_service:
            return
        
        logger.info(f"Exécution action: {action} sur {self.selected_service['name']}")
        
        if not self.root_mode:
            logger.warning("Tentative d'exécution sans privilèges root")
            messagebox.showerror(
                "Privilèges insuffisants",
                "Cette interface doit être lancée avec sudo.\n\n"
                "Relancez avec : sudo bash config.sh"
            )
            return
        
        service = self.selected_service
        service_id = service["id"]
        
        script_path = f"scripts/{action}/{service_id}_{action}.sh"
        full_script_path = os.path.join(self.base_path, script_path)
        
        self.update_console(f"""{"="*70}
ACTION: {service['name']} - {action.upper()}
{"="*70}
Script: {script_path}

""")
        
        logger.info(f"Exécution du script: {full_script_path}")
        self.show_progress_bar()
        
        self.current_thread = threading.Thread(
            target=self.execute_script, 
            args=(full_script_path, service, action), 
            daemon=True
        )
        self.current_thread.start()
    
    def execute_script(self, script_path, service, action):
        """Exécute un script bash"""
        try:
            if not os.path.exists(script_path):
                self.update_console(f"ERREUR: Script non trouvé: {script_path}\n")
                logger.error(f"Script non trouvé: {script_path}")
                self.hide_progress_bar()
                return
            
            logger.info(f"Démarrage du processus: {script_path}")
            
            # Variables d'environnement
            env = os.environ.copy()
            env['SERVICE_ID'] = service['id']
            env['SERVICES_STATUS_FILE'] = self.variables.get('SERVICES_STATUS_FILE')
            
            self.current_process = subprocess.Popen(
                ["bash", script_path],
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE, 
                text=True, 
                bufsize=1,
                env=env
            )
            
            for line in iter(self.current_process.stdout.readline, ''):
                if line:
                    if "PROGRESS:" in line:
                        progress_match = re.search(r'PROGRESS:(\d+):(.+)', line)
                        if progress_match:
                            progress_value = int(progress_match.group(1))
                            self.root.after(0, self.update_progress_bar, progress_value)
                            
                            # Si on détecte une fin d'étape dans full_install
                            if service['id'] == 'full_install' and 'Installation réussie' in line:
                                # Forcer un rafraîchissement des indicateurs
                                self.root.after(100, self.update_all_indicators)
                    elif "REFRESH_INDICATORS" in line:
                        # Signal explicite pour rafraîchir les indicateurs
                        logger.info("Signal de rafraîchissement reçu")
                        self.root.after(200, self.update_all_indicators)
                        # Ne pas afficher cette ligne dans la console
                        continue
                    else:
                        self.update_console(line)
            
            for line in iter(self.current_process.stderr.readline, ''):
                if line:
                    self.update_console(line, error=True)
            
            return_code = self.current_process.wait()
            logger.info(f"Script terminé avec code: {return_code}")
            
            self.root.after(0, self.hide_progress_bar)
            
            self.update_console(f"""
{"="*70}
TERMINÉ: {service['name']} - {action.upper()}
Code de sortie: {return_code}
{"="*70}

""")
            
            if return_code == 0 and action == "install":
                logger.info(f"Installation réussie pour {service['name']}")
                
                # Forcer le rafraîchissement immédiat des indicateurs
                # Le script a déjà mis à jour le fichier JSON
                # Utiliser un délai plus long pour s'assurer que le fichier est bien écrit
                self.root.after(1000, self.update_all_indicators)
                
                # Si c'est une installation complète, rafraîchir aussi après chaque étape
                if service_id == "full_install":
                    # Rafraîchir plus fréquemment pendant l'installation complète
                    for delay in [2000, 4000, 6000]:
                        self.root.after(delay, self.update_all_indicators)
                
                logger.info(f"Rafraîchissement des indicateurs déclenché")
            
        except Exception as e:
            logger.error(f"Erreur lors de l'exécution: {str(e)}")
            self.update_console(f"ERREUR: {str(e)}\n", error=True)
            self.root.after(0, self.hide_progress_bar)
        finally:
            self.current_process = None
            self.current_thread = None
    
    def update_console(self, text, error=False):
        """Met à jour la console de manière thread-safe"""
        self.root.after(0, self._update_console, text, error)
    
    def _update_console(self, text, error):
        """Met à jour la console (appelé dans le thread principal)"""
        self.console.config(state=tk.NORMAL)
        
        if error:
            self.console.tag_configure("error", foreground=COLORS["nord11"])
            self.console.insert(tk.END, text, "error")
        else:
            self.console.insert(tk.END, text)
        
        self.console.see(tk.END)
        self.console.config(state=tk.DISABLED)

# ===============================================================================
# POINT D'ENTRÉE
# ===============================================================================

if __name__ == "__main__":
    try:
        # Log de démarrage
        with open(log_file, 'a') as f:
            f.write("\n" + "="*80 + "\n")
            f.write(f"DÉMARRAGE: {script_name}\n")
            f.write(f"Description: Interface graphique MaxLink Admin Panel (Version simplifiée)\n")
            f.write(f"Date: {datetime.now().strftime('%c')}\n")
            f.write(f"Utilisateur: {os.environ.get('USER', 'unknown')}\n")
            f.write(f"Répertoire: {os.getcwd()}\n")
            f.write("="*80 + "\n\n")
        
        logger.info("Interface MaxLink démarrée (version simplifiée)")
        
        # Charger les variables
        base_path = os.path.dirname(os.path.abspath(__file__))
        variables = VariablesManager(base_path)
        logger.info("Variables chargées avec succès")
        
        # Créer l'interface
        root = tk.Tk()
        app = MaxLinkApp(root, variables)
        logger.info("Interface créée avec succès")
        root.mainloop()
        
    except Exception as e:
        logger.error(f"Erreur fatale: {e}")
        print(f"\nERREUR: {e}")
        sys.exit(1)
        
    finally:
        # Log de fin
        with open(log_file, 'a') as f:
            f.write("\n" + "="*80 + "\n")
            f.write(f"FIN: {script_name}\n")
            f.write(f"Date: {datetime.now().strftime('%c')}\n")
            f.write("="*80 + "\n\n")
        logger.info("Interface fermée")