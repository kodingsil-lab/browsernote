<?php

namespace App\Controllers\Api;

use App\Controllers\BaseController;
use App\Models\FolderModel;
use CodeIgniter\HTTP\ResponseInterface;

class FoldersApi extends BaseController
{
    private FolderModel $folders;

    public function __construct()
    {
        $this->folders = new FolderModel();
    }

    public function index()
    {
        $rows = db_connect()
            ->table('folders f')
            ->select('f.*, COUNT(n.id) AS note_count')
            ->join(
                'notes n',
                'n.folder_id = f.id AND n.is_deleted = 0 AND n.is_archived = 0',
                'left'
            )
            ->groupBy('f.id')
            ->orderBy('f.sort_order', 'ASC')
            ->orderBy('f.name', 'ASC')
            ->get()
            ->getResultArray();

        return $this->json([
            'ok'    => true,
            'count' => count($rows),
            'data'  => $rows,
        ]);
    }

    public function create()
    {
        $payload = $this->payload();
        $name = $this->normalizeName($payload['name'] ?? null);

        if ($name === null) {
            return $this->json([
                'ok'      => false,
                'message' => 'Nama folder wajib diisi.',
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        if ($this->nameExists($name)) {
            return $this->json([
                'ok'      => false,
                'message' => 'Nama folder sudah digunakan.',
            ], ResponseInterface::HTTP_CONFLICT);
        }

        $sortOrder = (int) (
            db_connect()
                ->table('folders')
                ->selectMax('sort_order', 'max_sort')
                ->get()
                ->getRowArray()['max_sort'] ?? 0
        ) + 1;

        $id = $this->folders->insert([
            'name'       => $name,
            'sort_order' => $sortOrder,
        ], true);

        if (!$id) {
            return $this->json([
                'ok'      => false,
                'message' => 'Folder gagal dibuat.',
                'errors'  => $this->folders->errors(),
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Folder dibuat.',
            'data'    => $this->findFolder((int) $id),
        ], ResponseInterface::HTTP_CREATED);
    }

    public function update(int $id)
    {
        $folder = $this->folders->find($id);

        if ($folder === null) {
            return $this->notFound();
        }

        $payload = $this->payload();
        $data = [];

        if (array_key_exists('name', $payload)) {
            $name = $this->normalizeName($payload['name']);

            if ($name === null) {
                return $this->json([
                    'ok'      => false,
                    'message' => 'Nama folder wajib diisi.',
                ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
            }

            if ($this->nameExists($name, $id)) {
                return $this->json([
                    'ok'      => false,
                    'message' => 'Nama folder sudah digunakan.',
                ], ResponseInterface::HTTP_CONFLICT);
            }

            $data['name'] = $name;
        }

        if (array_key_exists('sort_order', $payload)) {
            $data['sort_order'] = max(0, (int) $payload['sort_order']);
        }

        if ($data === []) {
            return $this->json([
                'ok'      => false,
                'message' => 'Tidak ada perubahan folder.',
            ], ResponseInterface::HTTP_BAD_REQUEST);
        }

        if (!$this->folders->update($id, $data)) {
            return $this->json([
                'ok'      => false,
                'message' => 'Folder gagal diperbarui.',
                'errors'  => $this->folders->errors(),
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Folder diperbarui.',
            'data'    => $this->findFolder($id),
        ]);
    }

    public function delete(int $id)
    {
        $folder = $this->folders->find($id);

        if ($folder === null) {
            return $this->notFound();
        }

        $db = db_connect();
        $db->transStart();

        $db->table('notes')
            ->where('folder_id', $id)
            ->update([
                'folder_id'  => null,
                'updated_at' => date('Y-m-d H:i:s'),
            ]);

        $db->table('folders')
            ->where('id', $id)
            ->delete();

        $db->transComplete();

        if (!$db->transStatus()) {
            return $this->json([
                'ok'      => false,
                'message' => 'Folder gagal dihapus.',
            ], ResponseInterface::HTTP_INTERNAL_SERVER_ERROR);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Folder dihapus. Catatan dipindahkan ke Tanpa Folder.',
            'id'      => $id,
        ]);
    }

    private function payload(): array
    {
        $json = $this->request->getJSON(true);

        if (is_array($json)) {
            return $json;
        }

        $raw = $this->request->getRawInput();

        if (is_array($raw) && $raw !== []) {
            return $raw;
        }

        $post = $this->request->getPost();

        return is_array($post) ? $post : [];
    }

    private function normalizeName(mixed $name): ?string
    {
        $name = trim((string) $name);
        $name = preg_replace('/\s+/u', ' ', $name) ?? $name;

        if ($name === '') {
            return null;
        }

        return mb_substr($name, 0, 150);
    }

    private function nameExists(string $name, ?int $ignoreId = null): bool
    {
        $builder = db_connect()
            ->table('folders')
            ->where('LOWER(name)', mb_strtolower($name));

        if ($ignoreId !== null) {
            $builder->where('id !=', $ignoreId);
        }

        return $builder->countAllResults() > 0;
    }

    private function findFolder(int $id): ?array
    {
        $row = db_connect()
            ->table('folders f')
            ->select('f.*, COUNT(n.id) AS note_count')
            ->join(
                'notes n',
                'n.folder_id = f.id AND n.is_deleted = 0 AND n.is_archived = 0',
                'left'
            )
            ->where('f.id', $id)
            ->groupBy('f.id')
            ->get()
            ->getRowArray();

        return $row ?: null;
    }

    private function notFound()
    {
        return $this->json([
            'ok'      => false,
            'message' => 'Folder tidak ditemukan.',
        ], ResponseInterface::HTTP_NOT_FOUND);
    }

    private function json(array $payload, int $status = ResponseInterface::HTTP_OK)
    {
        return $this->response
            ->setStatusCode($status)
            ->setContentType('application/json')
            ->setJSON($payload);
    }
}