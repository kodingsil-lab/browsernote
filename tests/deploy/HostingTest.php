<?php
/** Run: php tests/deploy/HostingTest.php (requires local Composer dependencies). */
declare(strict_types=1);
$project = str_replace('\\', '/', dirname(__DIR__, 2));
// PHP on Windows accepts a root-relative path on the current project drive.
$hostPath = static fn (string $path): string => PHP_OS_FAMILY === 'Windows' ? substr($path, 2) : $path;
$testRoot = $project . '/build/deploy-test-' . bin2hex(random_bytes(4));
mkdir($testRoot, 0700, true);
$passed = 0;
function verify(bool $condition, string $message): void
{
    global $passed;
    if (!$condition) throw new RuntimeException($message);
    $passed++;
    echo "PASS: $message\n";
}
function helper(string ...$args): array
{
    global $project;
    $pipes = [];
    $process = proc_open([PHP_BINARY, $project . '/deploy/hosting.php', ...$args], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    if (!is_resource($process)) throw new RuntimeException('Cannot start helper');
    fclose($pipes[0]);
    $output = stream_get_contents($pipes[1]) . stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]);
    return [proc_close($process), $output];
}
function success(string ...$args): void
{
    [$exit, $output] = helper(...$args);
    if ($exit !== 0) throw new RuntimeException(implode(' ', $args) . "\n" . $output);
}
try {
    success('preflight');
    $env = $hostPath($testRoot . '/.env');
    success('init-env', $env);
    $originalEnv = file_get_contents($env);
    success('init-env', $env);
    verify(file_get_contents($env) === $originalEnv, 'Existing production env is not overwritten');
    success('init-env', $hostPath($testRoot . '/second.env'));
    verify(file_get_contents($testRoot . '/second.env') !== $originalEnv, 'Encryption keys are generated independently');
    verify(str_contains($originalEnv, 'DBDriver = SQLite3') && str_contains($originalEnv, 'CI_ENVIRONMENT = production'), 'Production configuration uses SQLite');
    [$exit] = helper('init-env', '/invalid/../env');
    verify($exit !== 0, 'Unsafe helper path is rejected');

    $release = $testRoot . '/release';
    mkdir($release . '/public', 0755, true);
    copy($project . '/public/index.php', $release . '/public/index.php');
    $cPanelHtaccess = $testRoot . '/cpanel.htaccess';
    file_put_contents($cPanelHtaccess, "# BEGIN cPanel-generated php ini directives, do not edit\n<IfModule php8_module>\nphp_flag log_errors On\n</IfModule>\n# END cPanel-generated php ini directives, do not edit\n");
    success('prepare-public', $hostPath($release), $hostPath($testRoot . '/.htpasswd'), $hostPath($cPanelHtaccess));
    $index = file_get_contents($release . '/public/index.php');
    $rules = file_get_contents($release . '/public/.htaccess');
    verify(str_contains($index, $hostPath($release) . '/app/Config/Paths.php'), 'Front controller points outside webroot to the release');
    verify(str_contains($rules, 'Require valid-user') && !str_contains($rules, 'Require local') && !str_contains($rules, '@@'), 'Hosting config enables password auth and resolves template placeholders');
    verify(str_contains($rules, 'cPanel-generated php ini directives') && str_contains($rules, 'php_flag log_errors On'), 'Managed cPanel htaccess block is preserved');
    verify(str_contains($rules, 'https://note.sil.web.id') && str_contains($rules, '.browsernote-maintenance'), 'HTTPS and maintenance are configured');
    file_put_contents($release . '/public/index.php', '<?php // Unexpected front controller');
    [$exit] = helper('prepare-public', $hostPath($release), $hostPath($testRoot . '/.htpasswd'));
    verify($exit !== 0, 'Unexpected front controller fails without publishing');

    // Isolated Paths: real app code/dependencies, fixture-only env and writable.
    mkdir($release . '/app/Config', 0755, true);
    mkdir($testRoot . '/writable/cache', 0700, true);
    mkdir($testRoot . '/writable/logs', 0700, true);
    $paths = [
        'systemDirectory' => $project . '/vendor/codeigniter4/framework/system',
        'appDirectory' => $project . '/app',
        'writableDirectory' => $testRoot . '/writable',
        'testsDirectory' => $project . '/tests',
        'viewDirectory' => $project . '/app/Views',
        'envDirectory' => $testRoot,
    ];
    $pathsPhp = "<?php\nnamespace Config;\nclass Paths {\n";
    foreach ($paths as $key => $value) $pathsPhp .= 'public string $' . $key . ' = ' . var_export($value, true) . ";\n";
    file_put_contents($release . '/app/Config/Paths.php', $pathsPhp . "}\n");
    $dbPath = $hostPath($testRoot . '/writable/browsernote.sqlite');
    success('migrate', $hostPath($release), $dbPath);
    $db = new SQLite3($dbPath);
    verify($db->querySingle('SELECT COUNT(*) FROM notes') === 0, 'First migration creates empty notes without importing local data');
    $db->exec('PRAGMA journal_mode=WAL');
    $db->exec("INSERT INTO notes (title, content, content_text) VALUES ('Deployment fixture', '<p>keep this note</p>', 'keep this note')");
    $backupPath = $hostPath($testRoot . '/snapshot.sqlite');
    success('backup-db', $dbPath, $backupPath);
    $backup = new SQLite3($backupPath, SQLITE3_OPEN_READONLY);
    verify($backup->querySingle('SELECT content_text FROM notes') === 'keep this note', 'Backup contains committed WAL data');
    verify($backup->querySingle('PRAGMA integrity_check') === 'ok', 'Backup database passes integrity check');
    $db->exec("UPDATE notes SET content_text = 'after backup'");
    verify($backup->querySingle('SELECT content_text FROM notes') === 'keep this note', 'Snapshot remains independent of subsequent writes');
    success('migrate', $hostPath($release), $dbPath);
    verify($db->querySingle('SELECT content_text FROM notes') === 'after backup', 'Repeated migration preserves existing notes');
    [$exit] = helper('backup-db', $dbPath, $backupPath);
    verify($exit !== 0, 'An existing backup cannot be overwritten');
    $backup->close(); $db->close();
    file_put_contents($env, str_replace('database.default.database = browsernote.sqlite', 'database.default.database = unexpected.sqlite', $originalEnv));
    [$exit] = helper('migrate', $hostPath($release), $dbPath);
    verify($exit !== 0 && !file_exists($testRoot . '/writable/unexpected.sqlite'), 'Unexpected database configuration fails before migrations');
    echo "\n$passed checks passed. Isolated artifacts: $testRoot\n";
} catch (Throwable $error) {
    fwrite(STDERR, $error->getMessage() . "\nFixture retained: $testRoot\n");
    exit(1);
}
