<?php

namespace App\Database\Seeds;

use CodeIgniter\Database\Seeder;

class BrowserNoteSeeder extends Seeder
{
    public function run()
    {
        $folderCount = $this->db->table('folders')->countAllResults();
        $noteCount   = $this->db->table('notes')->countAllResults();

        if ($folderCount === 0) {
            $this->db->table('folders')->insert([
                'name'       => 'Umum',
                'sort_order' => 0,
                'created_at' => date('Y-m-d H:i:s'),
                'updated_at' => date('Y-m-d H:i:s'),
            ]);
        }

        if ($noteCount === 0) {
            $folder = $this->db->table('folders')
                ->where('name', 'Umum')
                ->get()
                ->getRowArray();

            $this->db->table('notes')->insert([
                'folder_id'    => $folder['id'] ?? null,
                'title'        => 'Catatan awal',
                'content'      => '<h1>BrowserNote</h1><p>Catatan pertama siap digunakan.</p>',
                'content_text' => 'BrowserNote Catatan pertama siap digunakan.',
                'is_archived'  => 0,
                'is_deleted'   => 0,
                'created_at'   => date('Y-m-d H:i:s'),
                'updated_at'   => date('Y-m-d H:i:s'),
            ]);
        }
    }
}
