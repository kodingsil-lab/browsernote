<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

class CreateNotes extends Migration
{
    public function up()
    {
        $this->forge->addField([
            'id' => [
                'type'           => 'INTEGER',
                'unsigned'       => true,
                'auto_increment' => true,
            ],
            'folder_id' => [
                'type'     => 'INTEGER',
                'unsigned' => true,
                'null'     => true,
            ],
            'title' => [
                'type'       => 'VARCHAR',
                'constraint' => 255,
                'default'    => 'Catatan tanpa judul',
            ],
            'content' => [
                'type' => 'TEXT',
                'null' => true,
            ],
            'content_text' => [
                'type' => 'TEXT',
                'null' => true,
            ],
            'is_archived' => [
                'type'    => 'INTEGER',
                'default' => 0,
            ],
            'is_deleted' => [
                'type'    => 'INTEGER',
                'default' => 0,
            ],
            'archived_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
            'deleted_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
            'created_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
            'updated_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
        ]);

        $this->forge->addKey('id', true);
        $this->forge->addKey('folder_id');
        $this->forge->addKey('title');
        $this->forge->addKey('is_archived');
        $this->forge->addKey('is_deleted');

        $this->forge->addForeignKey(
            'folder_id',
            'folders',
            'id',
            'SET NULL',
            'CASCADE'
        );

        $this->forge->createTable('notes', true);
    }

    public function down()
    {
        $this->forge->dropTable('notes', true);
    }
}
