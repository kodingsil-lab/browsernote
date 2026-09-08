<?php

namespace App\Controllers\Api;

use App\Controllers\BaseController;
use CodeIgniter\HTTP\ResponseInterface;

class BackupApi extends BaseController
{
    public function download()
    {
        if (!class_exists(\SQLite3::class)) {
            return $this->error(
                'Ekstensi SQLite3 PHP tidak tersedia.',
                ResponseInterface::HTTP_INTERNAL_SERVER_ERROR
            );
        }

        $sourcePath = WRITEPATH . 'browsernote.sqlite';

        if (!is_file($sourcePath)) {
            return $this->error(
                'Database BrowserNote tidak ditemukan.',
                ResponseInterface::HTTP_NOT_FOUND
            );
        }

        $backupDir = WRITEPATH . 'backups';

        if (!is_dir($backupDir) && !mkdir($backupDir, 0775, true) && !is_dir($backupDir)) {
            return $this->error(
                'Folder backup tidak dapat dibuat.',
                ResponseInterface::HTTP_INTERNAL_SERVER_ERROR
            );
        }

        $filename = 'browsernote_backup_' . date('Ymd_His') . '.sqlite';
        $destinationPath = $backupDir . DIRECTORY_SEPARATOR . $filename;

        try {
            $source = new \SQLite3(
                $sourcePath,
                SQLITE3_OPEN_READONLY
            );

            $destination = new \SQLite3(
                $destinationPath,
                SQLITE3_OPEN_READWRITE | SQLITE3_OPEN_CREATE
            );

            $success = $source->backup($destination);

            $destination->close();
            $source->close();

            if (!$success || !is_file($destinationPath)) {
                @unlink($destinationPath);

                return $this->error(
                    'Snapshot SQLite gagal dibuat.',
                    ResponseInterface::HTTP_INTERNAL_SERVER_ERROR
                );
            }
        } catch (\Throwable $e) {
            @unlink($destinationPath);

            log_message(
                'error',
                'BrowserNote backup failed: {message}',
                ['message' => $e->getMessage()]
            );

            return $this->error(
                'Backup SQLite gagal dibuat.',
                ResponseInterface::HTTP_INTERNAL_SERVER_ERROR
            );
        }

        return $this->response
            ->download($destinationPath, null)
            ->setFileName($filename);
    }

    private function error(string $message, int $status)
    {
        return $this->response
            ->setStatusCode($status)
            ->setContentType('application/json')
            ->setJSON([
                'ok'      => false,
                'message' => $message,
            ]);
    }
}