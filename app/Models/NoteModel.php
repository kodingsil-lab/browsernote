<?php

namespace App\Models;

use CodeIgniter\Model;

class NoteModel extends Model
{
    protected $table            = 'notes';
    protected $primaryKey       = 'id';
    protected $returnType       = 'array';
    protected $useAutoIncrement = true;

    protected $allowedFields = [
        'folder_id',
        'title',
        'content',
        'content_text',
        'is_archived',
        'is_deleted',
        'archived_at',
        'deleted_at',
    ];

    protected $useTimestamps = true;
    protected $createdField  = 'created_at';
    protected $updatedField  = 'updated_at';

    protected $validationRules = [
        'title' => 'permit_empty|max_length[255]',
    ];

    public function activeNotes()
    {
        return $this
            ->where('is_deleted', 0)
            ->where('is_archived', 0)
            ->orderBy('updated_at', 'DESC')
            ->findAll();
    }

    public function archivedNotes()
    {
        return $this
            ->where('is_deleted', 0)
            ->where('is_archived', 1)
            ->orderBy('archived_at', 'DESC')
            ->findAll();
    }

    public function trashedNotes()
    {
        return $this
            ->where('is_deleted', 1)
            ->orderBy('deleted_at', 'DESC')
            ->findAll();
    }

    public function searchNotes(string $query)
    {
        return $this
            ->groupStart()
                ->like('title', $query)
                ->orLike('content_text', $query)
            ->groupEnd()
            ->where('is_deleted', 0)
            ->orderBy('updated_at', 'DESC')
            ->findAll();
    }
}
