# Builds the Iron Brigade ReXGlue port on Windows: ReXGlue v0.11 with ReXNative's patches, built
# with LLVM 20 (clang++, lld) in the Visual Studio 2022 environment.
#
#   scripts\build.ps1 [-Stage sdk,game,install] [-Dest build] [-Jobs 10] [-Llvm <LLVM 20 bin>]
#                     [-SdkInstall <an installed ReXGlue SDK>] [-SdkSrc <its source tree>]
#                     [-FidelityFx <the FidelityFX SDK v2.4.0>] [-CopyGame]
#
# Stages:
#   sdk      ReXNative's scripts\build-sdk.ps1 (third_party\ReXNative): ReXGlue v0.11.0 at its
#            sdk\rexglue.lock with its sdk\patches\v0.11 (the host renderer's SDK side, codegen,
#            kernel and audio fixes), into $Dest\rexglue-sdk, $Dest\sdk-install, and the
#            FidelityFX SDK into $Dest\fidelityfx-sdk. Skip it and pass -SdkInstall / -SdkSrc to
#            reuse one built already (the same lock and patches).
#   game     tools\gen_manifest.py (codegen + function hints) and the game build in $Dest\game.
#   install  $Dest\IronBrigade: exe, the DLLs the build staged, ironbrigade.toml, game\
#            (-CopyGame) and the add-on in userdata\ (ReXGlue's content root).
param(
    [string]$Stage = 'sdk,game,install',
    [string]$Dest = "$PSScriptRoot\..\build",
    [string]$SdkSrc = '',
    [string]$SdkInstall = '',
    [string]$FidelityFx = '',
    [string]$Llvm = $env:REXNATIVE_LLVM,
    [int]$Jobs = 10,
    [string]$Tune = 'generic',
    [switch]$CopyGame
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..").Path
$Dest = [IO.Path]::GetFullPath($Dest)
if (-not $SdkSrc) { $SdkSrc = "$Dest\rexglue-sdk" }
if (-not $SdkInstall) { $SdkInstall = "$Dest\sdk-install" }
if (-not $FidelityFx) { $FidelityFx = "$Dest\fidelityfx-sdk" }
if (-not $Llvm) { $Llvm = 'C:\Program Files\LLVM\bin' }
# ReXNative: the third_party\ReXNative submodule, or a checkout beside this one.
$rexnative = @("$repo\third_party\ReXNative", "$repo\..\ReXNative") |
    Where-Object { Test-Path "$_\scripts\vcenv.cmd" } | Select-Object -First 1
if (-not $rexnative) { throw 'no ReXNative: clone with --recurse-submodules (third_party\ReXNative)' }
$vc = "$rexnative\scripts\vcenv.cmd"
# The game's code generation: AVX2 (the Steam Deck has it), precise floating point as the console
# computes it.
$flags = "-march=x86-64-v3 -mtune=$Tune -mprefer-vector-width=128 -ffp-model=precise -fno-math-errno -fno-char8_t -D_CRT_SECURE_NO_WARNINGS"
$stages = @($Stage -split ',' | ForEach-Object { $_ -split ' ' } | Where-Object { $_ })
# vcvars64 calls vswhere, which it expects on PATH.
$env:PATH = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer;$env:PATH"
New-Item -ItemType Directory -Force "$Dest\logs" | Out-Null
function Run([string]$cmd, [string]$log) {
    # The redirection is cmd's, so Windows PowerShell 5.1 never sees native stderr (with
    # ErrorActionPreference Stop it would turn vcvars' harmless warnings into a failure).
    cmd /c "call `"$vc`" && set `"PATH=$Llvm;%PATH%`" && $cmd > `"$Dest\logs\$log`" 2>&1"
    if ($LASTEXITCODE) { throw "$log failed (see $Dest\logs\$log)" }
}

if ($stages -contains 'sdk') {
    & "$rexnative\scripts\build-sdk.ps1" -Dest $Dest -SdkSrc $SdkSrc -FidelityFx $FidelityFx -Llvm $Llvm -Jobs $Jobs
    if (-not (Test-Path "$SdkInstall\bin\rexglue.exe")) {
        # build-sdk.ps1 installs into <Dest>\sdk-install.
        throw "no rexglue.exe in $SdkInstall"
    }
}

if ($stages -contains 'game') {
    $rex = "$SdkInstall\bin\rexglue.exe"
    python "$repo\tools\gen_manifest.py" --rexglue $rex
    if ($LASTEXITCODE) { throw 'codegen failed (see codegen.log)' }
    # A build folder of the v0.10 SDK (clang-cl) cannot be reused.
    if ((Test-Path "$Dest\game\CMakeCache.txt") -and
        (Select-String -Path "$Dest\game\CMakeCache.txt" -Pattern 'clang-cl' -Quiet)) {
        Remove-Item -Recurse -Force "$Dest\game"
    }
    Run "set `"CFLAGS=$flags`" && set `"CXXFLAGS=$flags`" && cmake -S `"$repo`" -B `"$Dest\game`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ `"-DCMAKE_PREFIX_PATH=$SdkInstall`" -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF `"-DIB_REXGLUE_SDK_SRC=$SdkSrc`" `"-DIB_FIDELITYFX_SDK=$FidelityFx`"" 'game-configure.log'
    Run "cmake --build `"$Dest\game`" -j $Jobs" 'game-build.log'
}

if ($stages -contains 'install') {
    $out = "$Dest\IronBrigade"
    New-Item -ItemType Directory -Force $out | Out-Null
    Get-ChildItem "$Dest\game" -Include ironbrigade*.exe, ironbrigade*.pdb -Recurse -Depth 2 |
        Where-Object FullName -notmatch 'CMakeFiles' | Copy-Item -Destination $out -Force
    # Every DLL the build staged beside the executable: ReXGlue's modules and GPU drivers, SDL3,
    # NVIDIA DLSS / DLSS 5 and AMD FidelityFX (rexnative_add); the v0.10 SDK's DLLs go.
    $staged = @(Get-ChildItem "$Dest\game\*.dll" | ForEach-Object { $_.Name.ToLower() })
    Get-ChildItem "$out\*.dll" | Where-Object {
        ($_.Name -like 'rex*' -or $_.Name -eq 'amd_fidelityfx_dx12.dll') -and
        ($staged -notcontains $_.Name.ToLower()) } | Remove-Item -Force
    Copy-Item "$Dest\game\*.dll" $out -Force
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
