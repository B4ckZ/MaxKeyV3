<?php
$archivesPath = '/var/www/maxlink-dashboard/archives';

function isValidFilename($filename) {
    return preg_match('/^S\d+_\d{4}_[a-zA-Z0-9_\-]+\.csv$/', $filename);
}

function isValidPath($path) {
    return strpos(realpath($path), realpath($GLOBALS['archivesPath'])) === 0;
}

function formatFileSize($bytes) {
    $units = ['B', 'KB', 'MB', 'GB'];
    $bytes = max($bytes, 0);
    $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
    $pow = min($pow, count($units) - 1);
    $bytes /= pow(1024, $pow);
    return round($bytes, 2) . ' ' . $units[$pow];
}

try {
    if (isset($_GET['file']) && isset($_GET['year'])) {
        $filename = $_GET['file'];
        $year = intval($_GET['year']);
        
        if (!isValidFilename($filename)) {
            http_response_code(400);
            die('Nom de fichier invalide');
        }
        
        if ($year < 2020 || $year > 2030) {
            http_response_code(400);
            die('Année invalide');
        }
        
        $filePath = $archivesPath . '/' . $year . '/' . $filename;
        
        if (!isValidPath($filePath)) {
            http_response_code(403);
            die('Accès refusé');
        }
        
        if (!file_exists($filePath)) {
            http_response_code(404);
            die('Fichier non trouvé');
        }
        
        $fileSize = filesize($filePath);
        
        header('Content-Type: text/csv');
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        header('Content-Length: ' . $fileSize);
        header('Cache-Control: no-cache, must-revalidate');
        header('Expires: 0');
        
        readfile($filePath);
        exit;
    }
    
    if (isset($_GET['week']) && isset($_GET['year'])) {
        $year = intval($_GET['year']);
        $week = intval($_GET['week']);
        
        if ($year < 2020 || $year > 2030) {
            http_response_code(400);
            die('Année invalide');
        }
        
        if ($week < 1 || $week > 53) {
            http_response_code(400);
            die('Semaine invalide');
        }
        
        $yearPath = $archivesPath . '/' . $year;
        
        if (!is_dir($yearPath)) {
            http_response_code(404);
            die('Année non trouvée dans les archives');
        }
        
        $weekPattern = sprintf('S%02d_%d_*.csv', $week, $year);
        $weekFiles = glob($yearPath . '/' . $weekPattern);
        
        if (empty($weekFiles)) {
            http_response_code(404);
            die('Aucun fichier trouvé pour cette semaine');
        }
        
        $downloadList = [];
        $totalSize = 0;
        
        foreach ($weekFiles as $filePath) {
            $filename = basename($filePath);
            $fileSize = filesize($filePath);
            $totalSize += $fileSize;
            
            $downloadList[] = [
                'filename' => $filename,
                'size' => $fileSize,
                'sizeFormatted' => formatFileSize($fileSize),
                'downloadUrl' => 'download-archive.php?file=' . urlencode($filename) . '&year=' . $year
            ];
        }
        
        header('Content-Type: application/json');
        echo json_encode([
            'week' => $week,
            'year' => $year,
            'fileCount' => count($downloadList),
            'totalSize' => $totalSize,
            'totalSizeFormatted' => formatFileSize($totalSize),
            'files' => $downloadList
        ]);
        exit;
    }
    
    if (isset($_GET['help']) || (!isset($_GET['file']) && !isset($_GET['week']))) {
        header('Content-Type: application/json');
        echo json_encode([
            'usage' => [
                'Fichier individuel' => 'download-archive.php?file=S01_2025_machine1.csv&year=2025',
                'Semaine complète (liste)' => 'download-archive.php?week=1&year=2025'
            ],
            'formats' => [
                'Fichier individuel' => 'CSV direct',
                'Semaine complète' => 'JSON avec liste des fichiers CSV à télécharger'
            ]
        ]);
        exit;
    }
    
    http_response_code(400);
    die('Paramètres manquants. Utilisez ?help pour voir les options disponibles.');
    
} catch (Exception $e) {
    http_response_code(500);
    die('Erreur serveur: ' . $e->getMessage());
}
?>