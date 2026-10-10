param([string]$Distribution = 'Cardinal3DBuild', [int]$Jobs = 4)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$linuxProject = (& wsl.exe -d $Distribution -u root -- wslpath -a $project).Trim()
if ($LASTEXITCODE -ne 0) { throw "Cannot access WSL builder $Distribution" }
# Keep sources and compiler caches in Linux storage; upstream cannot build in paths with spaces.
& wsl.exe -d $Distribution -u root -- bash -c 'set -e; mkdir -p /root/cardinal3d; rsync -a --exclude=.git --exclude=vendor --exclude=build --exclude=dist --exclude=.tools --exclude=setup --exclude=.godot --exclude=__pycache__ "$1/" /root/cardinal3d/; cd /root/cardinal3d; sed -i "s/\r$//" scripts/*.sh; CARDINAL_3D_BUILD_JOBS="$2" CARDINAL_3D_INSTALL_BUILD_DEPS=1 bash scripts/build_windows.sh; mkdir -p "$1/dist"; cp -a dist/. "$1/dist/"' build $linuxProject $Jobs
if ($LASTEXITCODE -ne 0) { throw 'Local build failed; compiler caches have been retained for the next attempt.' }
Write-Host "Local Windows bundle built in $project\dist"
