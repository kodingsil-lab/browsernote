<?php

namespace App\Controllers;

class Notes extends BaseController
{
    public function index()
    {
        helper('url');

        return view('notes/index');
    }
}