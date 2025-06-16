#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
===============================================================================
MAXLINK™ ADMIN PANEL - VERSION SIMPLIFIÉE
Interface d'administration avec installation complète uniquement
Version 3.0 - © 2025 WERIT. Tous droits réservés.
===============================================================================
"""

import tkinter as tk
from tkinter import scrolledtext, messagebox
import subprocess
import threading
import os
import sys
import json
import time
import re
import logging
from datetime import datetime

# ===============================================================================
# CONFIGURATION
# ===============================================================================

# Thème Nord
COLORS = {
    "nord0": "#2E3440",   # Fond principal
    "nord1": "#3B4252",   # Fond secondaire
    "nord2": "#434C5E",   # Fond tertiaire
    "nord3": "#4C566A",   # Bordures/Séparateurs
    "nord4": "#D8DEE9",   # Texte principal
    "nord5": "#E5E9F0",   # Texte secondaire
    "nord6": "#ECEFF4",   # Texte clair
    "nord7": "#8FBCBB",   # Accent turquoise
    "nord8": "#88C0D0",   # Accent bleu clair
    "nord9": "#81A1C1",   # Accent bleu
    "nord10": "#5E81AC",  # Accent bleu foncé
    "nord11": "#BF616A",  # Rouge (erreur)
    "nord12": "#D08770",  # Orange
    "nord13": "#EBCB8B",  # Jaune
    "nord14": "#A3BE8C",  # Vert (succès)
    "nord15": "#B48EAD"   # Violet
}

# ===============================================================================
# LOGGING
# ===============================================================================

# Configuration du logger
log_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs", "python")
os.makedirs(log_dir, exist_ok=True)

log_file = os.path.join(log_dir, f"interface_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger("MaxLinkApp")

# ===============================================================================
# GESTIONNAIRE DE STATUTS
# ===============================================================================

class StatusManager:
    """Gestionnaire unifié des statuts de services"""
    
    def __init__(self):
        self.status_file = '/var/lib/maxlink/services_status.json'
        self._ensure_file_exists()
    
    def _ensure_file_exists(self):
        """S'assure que le fichier de statuts existe"""
        os.makedirs(os.path.dirname(self.status_file), exist_ok=True)
        if not os.path.exists(self.status_file):
            with open(self.status_file, 'w') as f:
                json.dump({}, f)
    
    def load_statuses(self):
        """Charge tous les statuts depuis le fichier"""
        try:
            with open(self.status_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Erreur lors du chargement des statuts: {e}")
            return {}
    
    def is_active(self, service_id):
        """Vérifie si un service est actif"""
        statuses = self.load_statuses()
        return statuses.get(service_id, {}).get('status', 'inactive') == 'active'

# ===============================================================================
# CHARGEUR DE VARIABLES
# ===============================================================================

class VariablesLoader:
    """Charge les variables depuis variables.sh"""
    
    def __init__(self):
        self.variables = {}
        self.services = []
        self.load_variables()
    
    def load_variables(self):
        """Charge les variables depuis le fichier shell"""
        try:
            base_path = os.path.dirname(os.path.abspath(__file__))
            variables_path = os.path.join(base_path, "scripts", "common", "variables.sh")
            
            if not os.path.exists(variables_path):
                logger.error(f"Fichier variables.sh non trouvé: {variables_path}")
                raise FileNotFoundError(f"variables.sh non trouvé")
            
            with open(variables_path, 'r') as f:
                content = f.read()
            
            # Parser les variables
            for line in content.split('\n'):
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    match = re.match(r'^export\s+(\w+)="?([^"]*)"?$', line)
                    if match:
                        key = match.group(1)
                        value = match.group(2)
                        self.variables[key] = value
            
            # Valeurs par défaut
            if 'SERVICES_STATUS_FILE' not in self.variables:
                self.variables['SERVICES_STATUS_FILE'] = '/var/lib/maxlink/services_status.json'
            
            # Services disponibles (ordre fixe) - sans le meta service
            self.services = [
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
        
        logger.info("Initialisation de l'application MaxLink (version simplifiée)")
        
        self.base_path = os.path.dirname(os.path.abspath(__file__))
        
        # Configuration de la fenêtre
        self.root.title(self.variables.get_window_title())
        self.root.geometry("1450x750")
        self.root.configure(bg=COLORS["nord0"])
        
        self.center_window()
        
        # Vérifier les privilèges root
        self.root_mode = self.check_root_mode()
        logger.info(f"Mode root: {self.root_mode}")
        
        # Gestionnaire de statuts unifié
        self.status_manager = StatusManager()
        
        # Services disponibles
        self.services = self.variables.get_services_list()
        
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
        """Recharge tous les statuts et met à jour l'interface"""
        self.update_all_indicators()
        logger.debug("Rafraîchissement des indicateurs effectué")
    
    def periodic_refresh(self):
        """Rafraîchissement périodique simple"""
        # Ne rafraîchir que si aucune installation en cours
        if self.current_thread is None:
            self.refresh_all_statuses()
        # Répéter toutes les 2 secondes
        self.root.after(2000, self.periodic_refresh)
    
    def update_all_indicators(self):
        """Met à jour tous les indicateurs visuels"""
        current_statuses = self.status_manager.load_statuses()
        
        for service in self.services:
            if "indicator" in service:
                is_active = current_statuses.get(service['id'], {}).get('status', 'inactive') == 'active'
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
            text="État des Services",
            font=("Arial", 18, "bold"),
            bg=COLORS["nord1"],
            fg=COLORS["nord6"]
        )
        services_title.pack(pady=(0, 20))
        
        # Info texte
        info_label = tk.Label(
            services_frame,
            text="Les services seront installés dans l'ordre",
            font=("Arial", 11, "italic"),
            bg=COLORS["nord1"],
            fg=COLORS["nord5"]
        )
        info_label.pack(pady=(0, 15))
        
        # Créer les services (non cliquables)
        for service in self.services:
            self.create_service_item(services_frame, service)
        
        # Zone du bouton
        buttons_frame = tk.Frame(self.left_frame, bg=COLORS["nord1"], padx=20, pady=20)
        buttons_frame.pack(fill="x")
        
        self.create_action_button(buttons_frame)
        
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
        """Crée un élément de service (non cliquable)"""
        frame = tk.Frame(
            parent,
            bg=COLORS["nord1"],
            highlightthickness=2,
            highlightbackground=COLORS["nord3"],
            highlightcolor=COLORS["nord3"],
            padx=15,
            pady=10
        )
        frame.pack(fill="x", pady=8)
        
        # Nom du service
        label = tk.Label(
            frame, 
            text=service["name"],
            font=("Arial", 14, "bold"),
            bg=COLORS["nord1"],
            fg=COLORS["nord6"]
        )
        label.pack(side="left", fill="both", expand=True)
        
        # Indicateur de statut
        is_active = self.status_manager.is_active(service['id'])
        status_color = COLORS["nord14"] if is_active else COLORS["nord11"]
        
        indicator = tk.Canvas(frame, width=20, height=20, bg=COLORS["nord1"], highlightthickness=0)
        indicator.pack(side="right", padx=10)
        indicator.create_oval(2, 2, 18, 18, fill=status_color, outline="")
        
        service["frame"] = frame
        service["indicator"] = indicator
    
    def create_action_button(self, parent):
        """Crée le bouton d'installation complète"""
        button_style = {
            "font": ("Arial", 16, "bold"),
            "width": 25,
            "height": 2,
            "borderwidth": 0,
            "highlightthickness": 0,
            "cursor": "hand2"
        }
        
        btn = tk.Button(
            parent, 
            text="Installation Complète",
            bg=COLORS["nord10"],
            fg=COLORS["nord6"],
            command=self.run_full_install,
            **button_style
        )
        btn.pack(fill="x", pady=8)
        
        # Ajouter les effets hover
        btn.bind("<Enter>", lambda e: btn.config(bg=COLORS["nord9"]))
        btn.bind("<Leave>", lambda e: btn.config(bg=COLORS["nord10"]))
    
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
    
    def run_full_install(self):
        """Lance l'installation complète"""
        logger.info("Lancement de l'installation complète")
        
        if not self.root_mode:
            logger.warning("Tentative d'installation sans privilèges root")
            messagebox.showerror(
                "Privilèges Insuffisants",
                "L'installation complète nécessite les privilèges root.\n\n"
                "Veuillez relancer l'interface avec:\nsudo bash config.sh"
            )
            return
        
        if self.current_thread and self.current_thread.is_alive():
            logger.warning("Installation déjà en cours")
            messagebox.showwarning(
                "Installation en cours",
                "Une installation est déjà en cours.\nVeuillez patienter."
            )
            return
        
        # Confirmation
        response = messagebox.askyesno(
            "Confirmation",
            "Lancer l'installation complète de MaxLink?\n\n"
            "Cette opération installera tous les composants\n"
            "et prendra environ 10-15 minutes.\n\n"
            "Continuer?"
        )
        
        if not response:
            return
        
        # Lancer dans un thread séparé
        self.current_thread = threading.Thread(
            target=self.execute_full_install,
            daemon=True
        )
        self.current_thread.start()
    
    def execute_full_install(self):
        """Exécute l'installation complète"""
        script_path = os.path.join(
            self.base_path,
            "scripts",
            "install",
            "full_install_install.sh"
        )
        
        if not os.path.exists(script_path):
            logger.error(f"Script non trouvé: {script_path}")
            self.update_console(f"ERREUR: Script non trouvé: {script_path}\n", error=True)
            return
        
        try:
            logger.info(f"Exécution du script: {script_path}")
            
            self.update_console(f"""
{"="*70}
DÉMARRAGE: Installation complète de MaxLink
Script: {script_path}
{"="*70}

""")
            
            self.root.after(0, self.show_progress_bar)
            
            env = os.environ.copy()
            env['PYTHONUNBUFFERED'] = '1'
            env['SKIP_REBOOT'] = 'true'
            env['INTERFACE_MODE'] = 'true'  # Activer le mode interface pour logging.sh
            
            self.current_process = subprocess.Popen(
                ['bash', script_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
                bufsize=1,
                env=env
            )
            
            # Lire la sortie ligne par ligne
            for line in iter(self.current_process.stdout.readline, ''):
                if line:
                    # Traiter les lignes de progression
                    if line.startswith("PROGRESS:"):
                        parts = line.strip().split(":")
                        if len(parts) >= 3:
                            try:
                                progress = int(parts[1])
                                self.root.after(0, self.update_progress_bar, progress)
                            except ValueError:
                                pass
                    elif "Installation réussie" in line:
                        # Forcer un rafraîchissement des indicateurs
                        self.root.after(100, self.update_all_indicators)
                    elif "REFRESH_INDICATORS" in line:
                        # Signal explicite pour rafraîchir
                        logger.info("Signal de rafraîchissement reçu")
                        self.root.after(200, self.update_all_indicators)
                        continue
                    else:
                        self.update_console(line)
            
            for line in iter(self.current_process.stderr.readline, ''):
                if line:
                    self.update_console(line, error=True)
            
            return_code = self.current_process.wait()
            logger.info(f"Installation terminée avec code: {return_code}")
            
            self.root.after(0, self.hide_progress_bar)
            
            self.update_console(f"""
{"="*70}
TERMINÉ: Installation complète
Code de sortie: {return_code}
{"="*70}

""")
            
            if return_code == 0:
                logger.info("Installation complète réussie")
                # Rafraîchissement final
                self.root.after(1000, self.update_all_indicators)
                
                # Message de succès
                self.root.after(
                    1500,
                    lambda: messagebox.showinfo(
                        "Installation Réussie",
                        "L'installation complète de MaxLink s'est terminée avec succès!\n\n"
                        "Tous les services sont maintenant opérationnels."
                    )
                )
            else:
                self.root.after(
                    500,
                    lambda: messagebox.showerror(
                        "Erreur d'Installation",
                        f"L'installation a échoué avec le code: {return_code}\n\n"
                        "Consultez la console pour plus de détails."
                    )
                )
            
        except Exception as e:
            logger.error(f"Erreur lors de l'exécution: {str(e)}")
            self.update_console(f"ERREUR: {str(e)}\n", error=True)
            self.root.after(0, self.hide_progress_bar)
        
        finally:
            self.current_process = None
    
    def update_console(self, text, error=False):
        """Met à jour la console avec du texte"""
        def update():
            self.console.config(state=tk.NORMAL)
            
            # Configuration des tags
            if error:
                self.console.tag_config("error", foreground=COLORS["nord11"])
                self.console.insert(tk.END, text, "error")
            else:
                self.console.insert(tk.END, text)
            
            # Auto-scroll
            self.console.see(tk.END)
            self.console.config(state=tk.DISABLED)
        
        self.root.after(0, update)
    
    def on_closing(self):
        """Gestion de la fermeture de l'application"""
        if self.current_thread and self.current_thread.is_alive():
            response = messagebox.askyesno(
                "Installation en cours",
                "Une installation est en cours.\n\n"
                "Voulez-vous vraiment quitter?"
            )
            if not response:
                return
        
        logger.info("Fermeture de l'application")
        self.root.destroy()

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

def main():
    """Point d'entrée principal"""
    try:
        logger.info("="*70)
        logger.info("Démarrage de MaxLink Admin Panel (version simplifiée)")
        logger.info("="*70)
        
        # Charger les variables
        variables = VariablesLoader()
        
        # Créer l'interface
        root = tk.Tk()
        app = MaxLinkApp(root, variables)
        
        # Gestion de la fermeture
        root.protocol("WM_DELETE_WINDOW", app.on_closing)
        
        # Lancer l'interface
        logger.info("Interface prête")
        root.mainloop()
        
    except Exception as e:
        logger.error(f"Erreur fatale: {str(e)}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    main()