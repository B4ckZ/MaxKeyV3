<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');
header('Access-Control-Allow-Headers: Content-Type');

$archivesPath = '/var/www/maxlink-dashboard/archives';

try {
    $archives = [];
    
    if (!is_dir($archivesPath)) {
        echo json_encode([]);
        exit;
    }
    
    $yearDirs = glob($archivesPath . '/*', GLOB_ONLYDIR);
    
    foreach ($yearDirs as $yearDir) {
        $year = basename($yearDir);
        
        if (!preg_match('/^\d{4}$/', $year)) {
            continue;
        }
        
        $weeks = [];
        $csvFiles = glob($yearDir . '/S*_' . $year . '_*.csv');
        
        foreach ($csvFiles as $csvFile) {
            $filename = basename($csvFile);
            
            if (preg_match('/^S(\d+)_' . $year . '_(.*)\.csv$/', $filename, $matches)) {
                $week = intval($matches[1]);
                $machine = $matches[2];
                
                if ($week >= 1 && $week <= 53) {
                    if (!isset($weeks[$week])) {
                        $weeks[$week] = [
                            'week' => $week,
                            'files' => [],
                            'totalSize' => 0,
                            'fileCount' => 0
                        ];
                    }
                    
                    $fileSize = filesize($csvFile);
                    $weeks[$week]['files'][] = [
                        'filename' => $filename,
                        'machine' => $machine,
                        'size' => $fileSize,
                        'sizeFormatted' => formatFileSize($fileSize),
                        'downloadUrl' => "download-archive.php?file=" . urlencode($filename) . "&year=" . $year
                    ];
                    
                    $weeks[$week]['totalSize'] += $fileSize;
                    $weeks[$week]['fileCount']++;
                }
            }
        }
        
        foreach ($weeks as $weekNum => &$weekData) {
            $weekData['totalSizeFormatted'] = formatFileSize($weekData['totalSize']);
            $weekData['downloadAllUrl'] = "download-archive.php?week=" . $weekNum . "&year=" . $year;
        }
        
        krsort($weeks);
        
        if (!empty($weeks)) {
            $archives[$year] = array_values($weeks);
        }
    }
    
    krsort($archives);
    echo json_encode($archives, JSON_PRETTY_PRINT);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Erreur lecture archives: ' . $e->getMessage()]);
}

function formatFileSize($bytes) {
    $units = ['B', 'KB', 'MB', 'GB'];
    $bytes = max($bytes, 0);
    $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
    $pow = min($pow, count($units) - 1);
    $bytes /= pow(1024, $pow);
    return round($bytes, 2) . ' ' . $units[$pow];
}
?>