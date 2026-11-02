<#
.SYNOPSIS
    Links the repo addon folders into WoW's AddOns directory so edits are live.

.DESCRIPTION
    Replaces the copied ForeverHearthstone folder (and APIProbe with -IncludeAPIProbe) under
    Interface\AddOns with NTFS directory junctions pointing at this repo.
    After that, saving a .lua file here IS the installed file -- `/reload`
    in the client is the whole deploy step. No copy, no install script.

    Junctions need no elevation and no Developer Mode. WoW reads through them
    as ordinary directories. SavedVariables live in WTF\, not in the addon
    folder, so nothing player-owned is touched.

    Run once. Use -Unlink to go back to real copied folders.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\link-dev.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\link-dev.ps1 -Unlink
#>
param(
    [string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns',
    [switch]$Unlink,
    [switch]$Force,
    [switch]$IncludeAPIProbe,
    # the developer screenshot tour (FHTour/, never packaged)
    [switch]$IncludeTour
)

$ErrorActionPreference = 'Stop'

$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$addonRoot  = (Resolve-Path -LiteralPath $AddOnsPath).Path
$addons     = @('ForeverHearthstone')
if ($IncludeAPIProbe) { $addons += 'APIProbe' }
if ($IncludeTour) { $addons += 'FHTour' }

function Get-LinkTarget {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $null }
    $target = $item.Target
    if ($target -is [array]) { $target = $target[0] }
    if ([string]::IsNullOrEmpty($target)) {
        # PS 5.1 can report an empty Target for junctions; fall back to fsutil.
        $raw = & cmd.exe /c dir /AL (Split-Path -Parent $Path) 2>$null | Select-String ([regex]::Escape((Split-Path -Leaf $Path)))
        if ($raw -match '\[(.+)\]') { $target = $matches[1] }
    }
    return $target
}

function Remove-Junction {
    param([string]$Path)
    # Directory.Delete on a reparse point removes ONLY the link.
    # Remove-Item -Recurse in PS 5.1 can follow the junction and delete the
    # repo behind it, so it must never be used here.
    [System.IO.Directory]::Delete($Path)
}

# WoW keeps handles open on loaded addon files. Swapping the folder while the
# client is running fails partway and leaves the AddOns dir in a half state.
$wow = Get-Process -Name 'Wow', 'WowClassic', 'WowT', 'WowB' -ErrorAction SilentlyContinue
if ($wow -and -not $Force) {
    Write-Output 'World of Warcraft is running. Close the client fully, then run this again.'
    Write-Output 'It is a one-time swap; after it, /reload is all you need. (-Force overrides.)'
    exit 1
}

if ($Unlink) {
    foreach ($addon in $addons) {
        $destination = Join-Path $addonRoot $addon
        $source      = Join-Path $sourceRoot $addon
        if (Get-LinkTarget -Path $destination) {
            Remove-Junction -Path $destination
            Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
            Write-Output "$addon : junction removed, real copy restored."
        } else {
            Write-Output "$addon : not a junction, left alone."
        }
    }
    Write-Output 'Unlinked. Edits now need tools\install-retail.ps1 again.'
    exit 0
}

$backupRoot = Join-Path $PSScriptRoot ('install-backups\pre-link-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$linked = 0

foreach ($addon in $addons) {
    $source      = Join-Path $sourceRoot $addon
    $destination = Join-Path $addonRoot $addon

    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Missing source folder: $source"
    }

    $existingTarget = Get-LinkTarget -Path $destination
    if ($existingTarget) {
        if ($existingTarget.TrimEnd('\') -ieq $source.TrimEnd('\')) {
            Write-Output "$addon : already linked -> $source"
            continue
        }
        Write-Output "$addon : relinking (was -> $existingTarget)"
        Remove-Junction -Path $destination
    } elseif (Test-Path -LiteralPath $destination) {
        # A real copied folder. Move it aside rather than delete it.
        $backup = Join-Path $backupRoot $addon
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Move-Item -LiteralPath $destination -Destination $backup
        Write-Output "$addon : old copy moved to $backup"
    }

    New-Item -ItemType Junction -Path $destination -Value $source | Out-Null
    $linked++
}

# Verify the client will actually see the repo's current files through the link.
foreach ($addon in $addons) {
    $destination = Join-Path $addonRoot $addon
    $toc = Join-Path $destination "$addon.toc"
    if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) {
        throw "Verification failed: $toc is not readable through the link."
    }
    $viaLink = (Get-FileHash -LiteralPath $toc -Algorithm SHA256).Hash
    $direct  = (Get-FileHash -LiteralPath (Join-Path $sourceRoot "$addon\$addon.toc") -Algorithm SHA256).Hash
    if ($viaLink -ne $direct) { throw "Verification failed: $addon toc differs through the link." }
    Write-Output "$addon : verified live."
}

Write-Output ''
Write-Output "Linked $linked folder(s). The repo IS the install now."
Write-Output 'Lua edits          -> /reload in the client.'
Write-Output '.toc or new files  -> full client restart (the file list is read at startup).'
Write-Output '.tga art           -> full client restart (textures are cached at startup).'
