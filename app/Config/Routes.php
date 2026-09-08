<?php

use CodeIgniter\Router\RouteCollection;

/**
 * @var RouteCollection $routes
 */
$routes->get('/', 'Notes::index');
// <BROWSERNOTE_STAGE03_API>
$routes->group('api', static function ($routes) {
    $routes->get('notes', 'Api\NotesApi::index');
    $routes->post('notes', 'Api\NotesApi::create');

    $routes->get('notes/(:num)', 'Api\NotesApi::show/$1');
    $routes->patch('notes/(:num)', 'Api\NotesApi::update/$1');

    $routes->post('notes/(:num)/archive', 'Api\NotesApi::archive/$1');
    $routes->post('notes/(:num)/restore-archive', 'Api\NotesApi::restoreArchive/$1');

    $routes->post('notes/(:num)/restore-trash', 'Api\NotesApi::restoreTrash/$1');
    $routes->delete('notes/(:num)/force', 'Api\NotesApi::forceDelete/$1');
    $routes->delete('notes/(:num)', 'Api\NotesApi::trash/$1');
});
// </BROWSERNOTE_STAGE03_API>
// <BROWSERNOTE_STAGE07_FOLDERS>
$routes->group('api', static function ($routes) {
    $routes->get('folders', 'Api\FoldersApi::index');
    $routes->post('folders', 'Api\FoldersApi::create');
    $routes->patch('folders/(:num)', 'Api\FoldersApi::update/$1');
    $routes->delete('folders/(:num)', 'Api\FoldersApi::delete/$1');
});
// </BROWSERNOTE_STAGE07_FOLDERS>
// <BROWSERNOTE_STAGE09_SEARCH>
$routes->get('api/search', 'Api\SearchApi::index');
// </BROWSERNOTE_STAGE09_SEARCH>
// <BROWSERNOTE_STAGE11_BACKUP>
$routes->get('api/backup/download', 'Api\BackupApi::download');
// </BROWSERNOTE_STAGE11_BACKUP>
