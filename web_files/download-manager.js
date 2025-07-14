class MaxLinkDownloader {
    constructor() {
        this.downloadDelay = 500;
        this.baseUrl = window.location.origin;
    }
    
    downloadSingleFile(filename, year) {
        const url = `${this.baseUrl}/download-archive.php?file=${encodeURIComponent(filename)}&year=${year}`;
        
        const link = document.createElement('a');
        link.href = url;
        link.download = filename;
        link.style.display = 'none';
        
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }
    
    async downloadWeekFiles(week, year) {
        try {
            const response = await fetch(`${this.baseUrl}/download-archive.php?week=${week}&year=${year}`);
            
            if (!response.ok) {
                throw new Error(`Erreur HTTP: ${response.status}`);
            }
            
            const data = await response.json();
            
            if (!data.files || data.files.length === 0) {
                alert(`Aucun fichier trouvé pour la semaine ${week} de ${year}`);
                return;
            }
            
            this.showDownloadNotification(data);
            
            for (let i = 0; i < data.files.length; i++) {
                const file = data.files[i];
                setTimeout(() => {
                    this.downloadSingleFile(file.filename, year);
                }, i * this.downloadDelay);
            }
            
            return data;
            
        } catch (error) {
            console.error('Erreur lors du téléchargement multiple:', error);
            alert(`Erreur lors du téléchargement des fichiers de la semaine ${week}/${year}`);
            throw error;
        }
    }
    
    showDownloadNotification(data) {
        const notification = document.createElement('div');
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: #27ae60;
            color: white;
            padding: 15px 20px;
            border-radius: 8px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
            z-index: 10000;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 300px;
            animation: slideIn 0.3s ease-out;
        `;
        
        if (!document.querySelector('#maxlink-animations')) {
            const style = document.createElement('style');
            style.id = 'maxlink-animations';
            style.textContent = `
                @keyframes slideIn {
                    from { transform: translateX(100%); opacity: 0; }
                    to { transform: translateX(0); opacity: 1; }
                }
            `;
            document.head.appendChild(style);
        }
        
        notification.innerHTML = `
            <div style="font-weight: bold; margin-bottom: 5px;">
                📥 Téléchargement en cours
            </div>
            <div style="font-size: 14px;">
                ${data.fileCount} fichiers CSV<br>
                Semaine ${data.week}/${data.year}<br>
                Taille: ${data.totalSizeFormatted}
            </div>
        `;
        
        document.body.appendChild(notification);
        
        setTimeout(() => {
            notification.style.animation = 'slideIn 0.3s ease-out reverse';
            setTimeout(() => {
                if (notification.parentNode) {
                    notification.parentNode.removeChild(notification);
                }
            }, 300);
        }, 5000);
    }
    
    initializeDownloadButtons() {
        document.querySelectorAll('[data-download-file]').forEach(button => {
            button.addEventListener('click', (e) => {
                e.preventDefault();
                const filename = button.getAttribute('data-download-file');
                const year = button.getAttribute('data-year');
                this.downloadSingleFile(filename, year);
            });
        });
        
        document.querySelectorAll('[data-download-week]').forEach(button => {
            button.addEventListener('click', async (e) => {
                e.preventDefault();
                const week = button.getAttribute('data-download-week');
                const year = button.getAttribute('data-year');
                
                button.disabled = true;
                const originalText = button.textContent;
                button.textContent = '⏳ Téléchargement...';
                
                try {
                    await this.downloadWeekFiles(week, year);
                } finally {
                    setTimeout(() => {
                        button.disabled = false;
                        button.textContent = originalText;
                    }, 2000);
                }
            });
        });
    }
}

document.addEventListener('DOMContentLoaded', () => {
    window.maxlinkDownloader = new MaxLinkDownloader();
    window.maxlinkDownloader.initializeDownloadButtons();
});