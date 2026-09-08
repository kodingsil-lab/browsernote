<?php

namespace App\Controllers\Api;

use App\Controllers\BaseController;
use CodeIgniter\HTTP\ResponseInterface;

class SearchApi extends BaseController
{
    public function index()
    {
        $query = trim((string) $this->request->getGet('q'));
        $status = strtolower(trim((string) $this->request->getGet('status')));
        $status = $status !== '' ? $status : 'all';

        $limit = (int) $this->request->getGet('limit');
        $limit = $limit > 0 ? min($limit, 100) : 50;

        if ($query === '') {
            return $this->json([
                'ok'    => true,
                'query' => '',
                'count' => 0,
                'data'  => [],
            ]);
        }

        if (!in_array($status, ['all', 'active', 'archived'], true)) {
            return $this->json([
                'ok'      => false,
                'message' => 'Status pencarian tidak valid.',
            ], ResponseInterface::HTTP_BAD_REQUEST);
        }

        $builder = db_connect()
            ->table('notes n')
            ->select(
                'n.id, n.folder_id, n.title, n.content_text, ' .
                'n.is_archived, n.is_deleted, n.created_at, n.updated_at, ' .
                'f.name AS folder_name'
            )
            ->join('folders f', 'f.id = n.folder_id', 'left')
            ->where('n.is_deleted', 0);

        if ($status === 'active') {
            $builder->where('n.is_archived', 0);
        } elseif ($status === 'archived') {
            $builder->where('n.is_archived', 1);
        }

        $builder
            ->groupStart()
                ->like('n.title', $query)
                ->orLike('n.content_text', $query)
            ->groupEnd()
            ->orderBy('n.updated_at', 'DESC')
            ->orderBy('n.id', 'DESC')
            ->limit($limit);

        $rows = $builder->get()->getResultArray();

        foreach ($rows as &$row) {
            $row['snippet'] = $this->makeSnippet(
                (string) ($row['content_text'] ?? ''),
                $query
            );

            unset($row['content_text']);
        }
        unset($row);

        return $this->json([
            'ok'     => true,
            'query'  => $query,
            'status' => $status,
            'count'  => count($rows),
            'data'   => $rows,
        ]);
    }

    private function makeSnippet(string $text, string $query): string
    {
        $text = trim(preg_replace('/\s+/u', ' ', $text) ?? $text);

        if ($text === '') {
            return '';
        }

        $position = mb_stripos($text, $query);

        if ($position === false) {
            return mb_strlen($text) > 120
                ? mb_substr($text, 0, 120) . '…'
                : $text;
        }

        $start = max(0, $position - 45);
        $length = 130;
        $snippet = mb_substr($text, $start, $length);

        if ($start > 0) {
            $snippet = '…' . $snippet;
        }

        if (($start + $length) < mb_strlen($text)) {
            $snippet .= '…';
        }

        return $snippet;
    }

    private function json(array $payload, int $status = ResponseInterface::HTTP_OK)
    {
        return $this->response
            ->setStatusCode($status)
            ->setContentType('application/json')
            ->setJSON($payload);
    }
}