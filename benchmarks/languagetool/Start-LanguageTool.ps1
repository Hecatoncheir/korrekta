param(
    [string]$Storage = 'E:\korrekta',
    [int]$Port = 8081
)

$ErrorActionPreference = 'Stop'
$runtimePath = Join-Path $Storage 'languagetool\6.8'
$javaPath = Join-Path $Storage 'runtimes\jdk-21.0.13+9-jre\bin\java.exe'
$libraryPath = Join-Path $runtimePath 'lib\*'
$statePath = Join-Path $runtimePath 'server-state.json'
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$state.pid)"
        if (($listener.OwningProcess -contains $state.pid) -and $existing.ExecutablePath -eq $javaPath -and $existing.CommandLine.Contains('org.languagetool.server.HTTPServer')) {
            Invoke-RestMethod "http://127.0.0.1:$Port/v2/languages" -TimeoutSec 3 | Out-Null
            Write-Output "LanguageTool уже работает: http://127.0.0.1:$Port"
            return
        }
    }
    throw "Порт $Port занят другим процессом. Выберите другой порт."
}
if (!(Test-Path -LiteralPath $javaPath) -or !(Test-Path -LiteralPath (Join-Path $runtimePath 'lib\languagetool-server-6.8.jar'))) {
    & python -X utf8 (Join-Path $PSScriptRoot 'prepare.py') --storage $Storage
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось подготовить LanguageTool. Подробности выше.' }
}
$temporaryPath = Join-Path $Storage 'tmp'
New-Item -ItemType Directory -Force -Path $temporaryPath | Out-Null
$configPath = Join-Path $runtimePath 'server.properties'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'server.properties') -Destination $configPath -Force
$arguments = @(
    '-Xms128m', '-Xmx1024m', '-Dfile.encoding=UTF-8',
    "-Djava.io.tmpdir=`"$temporaryPath`"", '-cp', "`"$libraryPath`"",
    'org.languagetool.server.HTTPServer', '--config', "`"$configPath`"", '--port', "$Port"
)
$server = Start-Process -FilePath $javaPath -ArgumentList $arguments -WorkingDirectory $runtimePath -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtimePath 'server.stdout.log') -RedirectStandardError (Join-Path $runtimePath 'server.stderr.log')
@{ pid = $server.Id; port = $Port; java = $javaPath; started = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    if ($server.HasExited) { throw 'LanguageTool завершился. Проверьте server.stderr.log.' }
    try {
        Invoke-RestMethod "http://127.0.0.1:$Port/v2/languages" -TimeoutSec 1 | Out-Null
        Write-Output "LanguageTool запущен: http://127.0.0.1:$Port, PID $($server.Id)"
        return
    } catch {
        Start-Sleep -Milliseconds 500
    }
}
throw 'Сервер ещё не готов. Проверьте журналы и server-state.json перед повторным запуском.'
