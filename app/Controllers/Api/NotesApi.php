<?php

namespace App\Controllers\Api;

use App\Controllers\BaseController;
use App\Models\FolderModel;
use App\Models\NoteModel;
use CodeIgniter\HTTP\ResponseInterface;

class NotesApi extends BaseController
{
    private NoteModel $notes;
    private FolderModel $folders;

    public function __construct()
    {
        $this->notes = new NoteModel();
        $this->folders = new FolderModel();
    }

    public function index()
    {
        $status = strtolower(trim((string) $this->request->getGet('status')));
        $status = $status !== '' ? $status : 'active';

        $builder = db_connect()
            ->table('notes n')
            ->select('n.*, f.name AS folder_name')
            ->join('folders f', 'f.id = n.folder_id', 'left');

        switch ($status) {
            case 'active':
                $builder
                    ->where('n.is_deleted', 0)
                    ->where('n.is_archived', 0);
                break;

            case 'archived':
                $builder
                    ->where('n.is_deleted', 0)
                    ->where('n.is_archived', 1);
                break;

            case 'trash':
                $builder->where('n.is_deleted', 1);
                break;

            case 'all':
                break;

            default:
                return $this->json([
                    'ok'      => false,
                    'message' => 'Status tidak valid.',
                ], ResponseInterface::HTTP_BAD_REQUEST);
        }

        $rows = $builder
            ->orderBy('n.updated_at', 'DESC')
            ->orderBy('n.id', 'DESC')
            ->limit(200)
            ->get()
            ->getResultArray();

        return $this->json([
            'ok'     => true,
            'status' => $status,
            'count'  => count($rows),
            'data'   => $rows,
        ]);
    }

    public function show(int $id)
    {
        $note = $this->findWithFolder($id);

        if ($note === null) {
            return $this->notFound();
        }

        return $this->json([
            'ok'   => true,
            'data' => $note,
        ]);
    }

    public function create()
    {
        $payload = $this->payload();

        $folderId = $this->normalizeFolderId($payload['folder_id'] ?? null);

        if ($folderId === false) {
            return $this->json([
                'ok'      => false,
                'message' => 'Folder tidak ditemukan.',
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        $title = $this->normalizeTitle($payload['title'] ?? null);
        $content = (string) ($payload['content'] ?? '');

        $id = $this->notes->insert([
            'folder_id'    => $folderId,
            'title'        => $title,
            'content'      => $content,
            'content_text' => $this->plainText($content),
            'is_archived'  => 0,
            'is_deleted'   => 0,
            'archived_at'  => null,
            'deleted_at'   => null,
        ], true);

        if (!$id) {
            return $this->json([
                'ok'      => false,
                'message' => 'Catatan gagal dibuat.',
                'errors'  => $this->notes->errors(),
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dibuat.',
            'data'    => $this->findWithFolder((int) $id),
        ], ResponseInterface::HTTP_CREATED);
    }

    public function update(int $id)
    {
        $current = $this->notes->find($id);

        if ($current === null) {
            return $this->notFound();
        }

        $payload = $this->payload();
        $data = [];

        if (array_key_exists('folder_id', $payload)) {
            $folderId = $this->normalizeFolderId($payload['folder_id']);

            if ($folderId === false) {
                return $this->json([
                    'ok'      => false,
                    'message' => 'Folder tidak ditemukan.',
                ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
            }

            $data['folder_id'] = $folderId;
        }

        if (array_key_exists('title', $payload)) {
            $data['title'] = $this->normalizeTitle($payload['title']);
        }

        if (array_key_exists('content', $payload)) {
            $content = (string) $payload['content'];
            $data['content'] = $content;
            $data['content_text'] = $this->plainText($content);
        }

        if ($data === []) {
            return $this->json([
                'ok'      => false,
                'message' => 'Tidak ada perubahan yang dikirim.',
            ], ResponseInterface::HTTP_BAD_REQUEST);
        }

        if (!$this->notes->update($id, $data)) {
            return $this->json([
                'ok'      => false,
                'message' => 'Catatan gagal diperbarui.',
                'errors'  => $this->notes->errors(),
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan diperbarui.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function archive(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        if ((int) $note['is_deleted'] === 1) {
            return $this->json([
                'ok'      => false,
                'message' => 'Catatan di Sampah tidak dapat langsung diarsipkan.',
            ], ResponseInterface::HTTP_CONFLICT);
        }

        $this->notes->update($id, [
            'is_archived' => 1,
            'archived_at' => date('Y-m-d H:i:s'),
        ]);

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan diarsipkan.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function restoreArchive(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        $this->notes->update($id, [
            'is_archived' => 0,
            'archived_at' => null,
        ]);

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dikembalikan dari Arsip.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function trash(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        $this->notes->update($id, [
            'is_deleted'  => 1,
            'deleted_at'  => date('Y-m-d H:i:s'),
            'is_archived' => 0,
            'archived_at' => null,
        ]);

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dipindahkan ke Sampah.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function restoreTrash(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        $this->notes->update($id, [
            'is_deleted' => 0,
            'deleted_at' => null,
        ]);

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dipulihkan dari Sampah.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function forceDelete(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        if ((int) $note['is_deleted'] !== 1) {
            return $this->json([
                'ok'      => false,
                'message' => 'Hapus permanen hanya diperbolehkan untuk catatan yang sudah berada di Sampah.',
            ], ResponseInterface::HTTP_CONFLICT);
        }

        db_connect()
            ->table('notes')
            ->where('id', $id)
            ->delete();

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dihapus permanen.',
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

    private function normalizeTitle(mixed $title): string
    {
        $title = trim((string) $title);

        if ($title === '') {
            return 'Catatan tanpa judul';
        }

        return mb_substr($title, 0, 255);
    }

    private function normalizeFolderId(mixed $folderId): int|null|false
    {
        if ($folderId === null || $folderId === '') {
            return null;
        }

        if (!is_numeric($folderId)) {
            return false;
        }

        $folderId = (int) $folderId;

        if ($folderId < 1 || $this->folders->find($folderId) === null) {
            return false;
        }

        return $folderId;
    }

    private function plainText(string $html): string
    {
        $text = html_entity_decode(
            strip_tags($html),
            ENT_QUOTES | ENT_HTML5,
            'UTF-8'
        );

        $text = preg_replace('/\s+/u', ' ', $text) ?? $text;

        return trim($text);
    }

    private function findWithFolder(int $id): ?array
    {
        $row = db_connect()
            ->table('notes n')
            ->select('n.*, f.name AS folder_name')
            ->join('folders f', 'f.id = n.folder_id', 'left')
            ->where('n.id', $id)
            ->get()
            ->getRowArray();

        return $row ?: null;
    }

    private function notFound()
    {
        return $this->json([
            'ok'      => false,
            'message' => 'Catatan tidak ditemukan.',
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