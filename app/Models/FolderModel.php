<?php

namespace App\Models;

use CodeIgniter\Model;

class FolderModel extends Model
{
    protected $table            = 'folders';
    protected $primaryKey       = 'id';
    protected $returnType       = 'array';
    protected $useAutoIncrement = true;

    protected $allowedFields = [
        'name',
        'sort_order',
    ];

    protected $useTimestamps = true;
    protected $createdField  = 'created_at';
    protected $updatedField  = 'updated_at';

    protected $validationRules = [
        'name' => 'required|max_length[150]',
    ];
}
