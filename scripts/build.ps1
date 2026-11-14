# Builds the Iron Brigade ReXGlue port on Windows with the Visual Studio 2022 clang-cl, lld-link
# and Windows SDK, the same way FromDustDeck's scripts\build.ps1 does.
#
#   scripts\build.ps1 [-Stage sdk,game,install] [-Dest build] [-Jobs 10] [-Tune znver2]
#                     [-SdkInstall <an installed ReXGlue SDK>] [-CopyGame]
#
# Stages:
#   sdk      ReXGlue at patches\rexglue.lock + patches\deck (generic and Deck patches from
#            PGR4Native) + patches\shared (the From Dust port's SDK changes: draw hooks for a
#            host renderer, codegen, memory). Skip it and pass -SdkInstall to reuse an identical
#            SDK: FromDustDeck's, or ReXNative's (third_party\ReXNative\scripts\build-sdk.ps1,
#            the same lock and patches).
#   game     tools\gen_manifest.py (codegen + function hints) and the game build in $Dest\game.
#   install  $Dest\IronBrigade: exe, SDK DLLs, ironbrigade.toml, game\ (-CopyGame) and the
#            add-on in userdata\ (ReXGlue's content root).
param(
    [string]$Stage = 'sdk,game,install',
    [string]$Dest = "$PSScriptRoot\..\build",
    [string]$SdkSrc = '',
    [string]$Tune = 'generic',
    [int]$Jobs = 10,
    [string]$SdkInstall = '',
    [switch]$CopyGame
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..").Path
$Dest = [IO.Path]::GetFullPath($Dest)
if (-not $SdkSrc) { $SdkSrc = "$Dest\rexglue-sdk" }
if (-not $SdkInstall) { $SdkInstall = "$Dest\sdk-install" }
# The Visual Studio x64 environment (vcvars64 through vswhere): ReXNative's script, from the
# third_party\ReXNative submodule or a ReXNative checkout beside this one; PGR4Native's otherwise.
$vc = @("$repo\third_party\ReXNative\scripts\vcenv.cmd", "$repo\..\ReXNative\scripts\vcenv.cmd",
        'F:\PGR4Native\scripts\windows\vcenv.cmd') | Where-Object { Test-Path $_ } |
    Select-Object -First 1
if (-not $vc) { throw 'no vcenv.cmd: clone with --recurse-submodules (third_party\ReXNative)' }
$flags = "/clang:-march=x86-64-v3 /clang:-mtune=$Tune /clang:-mprefer-vector-width=128 /clang:-ffp-model=precise /clang:-fno-math-errno /Zc:char8_t- -Wno-unknown-argument -Wno-unused-command-line-argument"
$stages = @($Stage -split ',' | ForEach-Object { $_ -split ' ' } | Where-Object { $_ })
# vcvars64 calls vswhere, which it expects on PATH.
$env:PATH = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer;$env:PATH"
New-Item -ItemType Directory -Force "$Dest\logs" | Out-Null
function Run([string]$cmd, [string]$log) {
    # The redirection is cmd's, so Windows PowerShell 5.1 never sees native stderr (with
    # ErrorActionPreference Stop it would turn vcvars' harmless warnings into a failure).
    cmd /c "call `"$vc`" $cmd > `"$Dest\logs\$log`" 2>&1"
    if ($LASTEXITCODE) { throw "$log failed (see $Dest\logs\$log)" }
}

if ($stages -contains 'sdk') {
    if (-not (Test-Path "$SdkSrc\.git")) {
        $lock = @{}
        Get-Content "$repo\patches\rexglue.lock" | Where-Object { $_ -match '^(\w+)=(.*)$' } |
            ForEach-Object { $lock[$Matches[1]] = $Matches[2] }
        # As F:\PGR4Native\scripts\windows\build.ps1 does: no CRLF conversion (the patches expect
        # the files as committed), and libmspack's git symlinks, which become text placeholders
        # without Windows developer mode, are replaced by copies of their targets.
        git clone -q --no-checkout --filter=blob:none $lock.REXGLUE_URL $SdkSrc
        git -C $SdkSrc config core.autocrlf false
        git -C $SdkSrc checkout -q $lock.REXGLUE_COMMIT
        git -C $SdkSrc submodule update -q --init --recursive --depth 1 --jobs 8
        git -C $SdkSrc submodule foreach -q --recursive 'git config core.autocrlf false'
        python -c @"
import subprocess, os, shutil
repo = r'$SdkSrc\thirdparty\libmspack'
for line in subprocess.run(['git','-C',repo,'ls-files','-s'],capture_output=True,text=True).stdout.splitlines():
    mode, _, _, path = line.split(None, 3)
    if mode == '120000':
        p = os.path.join(repo, path)
        shutil.copyfile(os.path.normpath(os.path.join(os.path.dirname(p), open(p).read().strip())), p)
"@
        $patches = @(Get-ChildItem "$repo\patches\deck\*.patch" | Sort-Object Name) +
                   @(Get-ChildItem "$repo\patches\shared\*.patch" | Sort-Object Name)
        foreach ($p in $patches) {
            git -C $SdkSrc apply --whitespace=nowarn $p.FullName
            if ($LASTEXITCODE) { throw "patch $($p.Name) does not apply" }
        }
    }
    $ffx = ''
    if (Test-Path "$Dest\fidelityfx-src") { $ffx = "`"-DFETCHCONTENT_SOURCE_DIR_FIDELITYFX=$Dest\fidelityfx-src`"" }
    Run "set `"CFLAGS=$flags`" && set `"CXXFLAGS=$flags`" && cmake -S `"$SdkSrc`" -B `"$Dest\sdk`" -G Ninja $ffx -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DCMAKE_LINKER=lld-link `"-DCMAKE_SHARED_LINKER_FLAGS_RELEASE=/INCREMENTAL:NO /MAP`" -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_ENABLE_FIDELITYFX=ON -DREXGLUE_USE_VULKAN=ON -DCMAKE_RC_COMPILER=rc `"-DCMAKE_INSTALL_PREFIX=$SdkInstall`"" 'sdk-configure.log'
    Run "cmake --build `"$Dest\sdk`" --target install -j $Jobs" 'sdk-build.log'
}

if ($stages -contains 'game') {
    $rex = "$SdkInstall\bin\rexglue.exe"
    python "$repo\tools\gen_manifest.py" --rexglue $rex
    if ($LASTEXITCODE) { throw 'codegen failed (see codegen.log)' }
    Run "set `"CFLAGS=$flags /D_CRT_SECURE_NO_WARNINGS`" && set `"CXXFLAGS=$flags /D_CRT_SECURE_NO_WARNINGS`" && cmake -S `"$repo`" -B `"$Dest\game`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DCMAKE_LINKER=lld-link `"-DCMAKE_PREFIX_PATH=$SdkInstall`" -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF" 'game-configure.log'
    Run "cmake --build `"$Dest\game`" -j $Jobs" 'game-build.log'
}

if ($stages -contains 'install') {
    $out = "$Dest\IronBrigade"
    New-Item -ItemType Directory -Force $out | Out-Null
    Get-ChildItem "$Dest\game" -Include ironbrigade*.exe, ironbrigade*.pdb -Recurse -Depth 2 |
        Where-Object FullName -notmatch 'CMakeFiles' | Copy-Item -Destination $out -Force
    # The SDK's DLLs: the runtime, the Xenos GPU plugin and AMD FidelityFX.
    Copy-Item "$SdkInstall\bin\*.dll" $out -Force
    # Kept once written (the user may edit it).
    if (-not (Test-Path "$out\ironbrigade.toml")) { Copy-Item "$repo\config\ironbrigade.toml" $out }
    if ($CopyGame) {
        robocopy "$repo\game-data" "$out\game" /E /NFL /NDL /NJH /NJS | Out-Null
        # The "Rise of the Martian Bear" add-on (marketplace content, type 00000002), extracted
        # from its LIVE package into the layout ReXGlue's ContentManager reads
        # (userdata\0000000000000000\58410A95\00000002\<package>\: xuid 0, marketplace).
        if (Test-Path "$repo\dlc-data") {
            robocopy "$repo\dlc-data" "$out\userdata" /E /NFL /NDL /NJH /NJS | Out-Null
        }
    }
    Get-ChildItem $out | Select-Object Name, Length
}
