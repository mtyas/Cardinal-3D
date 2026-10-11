param([string]$Distribution = 'Cardinal3DBuild', [ValidateRange(1,64)][int]$Jobs = 4, [switch]$PrepareOnly, [switch]$Embedded, [switch]$EmbeddedGraphics, [switch]$FullRegistry)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$linuxProject = (& wsl.exe -d $Distribution -u root -- wslpath -a $project).Trim()
if ($LASTEXITCODE -ne 0) { throw "Cannot access WSL builder $Distribution" }
# An LF-only driver also avoids nested shell quoting in Windows PowerShell 5.
$tools = Join-Path $project '.tools'
New-Item -ItemType Directory -Force $tools | Out-Null
$driver = Join-Path $tools 'local-builder.sh'
$program = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'local_windows_builder.sh')).Replace("`r", '')
[IO.File]::WriteAllText($driver, $program, [Text.UTF8Encoding]::new($false))
$linuxDriver = (& wsl.exe -d $Distribution -u root -- wslpath -a $driver).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the local build driver' }
$mode = if ($FullRegistry) { 'embedded-full' } elseif ($EmbeddedGraphics) { 'embedded-graphics' } elseif ($Embedded) { 'embedded' } else { 'runtime' }
& wsl.exe -d $Distribution -u root -- bash $linuxDriver $linuxProject $Jobs $PrepareOnly.IsPresent $mode
if ($LASTEXITCODE -ne 0) { throw 'Local build failed; compiler caches have been retained for the next attempt.' }
if ($PrepareOnly) { Write-Host 'Local source staging verified.' }
elseif ($FullRegistry) { Write-Host "Full embedded registry built in $project\dist\embedded-full" }
elseif ($Embedded -or $EmbeddedGraphics) { Write-Host "Experimental embedded host built in $project\dist\embedded" }
else { Write-Host "Local Windows bundle built in $project\dist" }
