param(
    [string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns',
    [switch]$IncludeAPIProbe
)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$addonRoot = (Resolve-Path -LiteralPath $AddOnsPath).Path
$backupRoot = Join-Path $PSScriptRoot ('install-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$updated = 0
$verified = 0
$addons = @('ForeverHearthstone')
if ($IncludeAPIProbe) { $addons += 'APIProbe' }
foreach ($addon in $addons) {
    $source = Join-Path $sourceRoot $addon
    $destination = Join-Path $addonRoot $addon
    if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
        throw "Expected existing addon folder: $destination"
    }
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
        if ($file.Extension -notin @('.lua', '.toc', '.tga', '.wav', '.ogg', '.mp3', '.json', '.md', '.ttf', '.txt')) { continue }
        $relative = $file.FullName.Substring($source.Length + 1)
        $target = Join-Path $destination $relative
        $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $same = (Test-Path -LiteralPath $target -PathType Leaf) -and
            ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $sourceHash)
        if (-not $same) {
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $backup = Join-Path (Join-Path $backupRoot $addon) $relative
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
                Copy-Item -LiteralPath $target -Destination $backup
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            $updated++
        }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $sourceHash) {
            throw "Verification failed: $target"
        }
        $verified++
    }
}
Write-Output "Updated $updated files; verified $verified installed files."
Write-Output "Replaced-file backups: $backupRoot"
Write-Output 'No files deleted. WTF/SavedVariables untouched. Restart WoW to load new textures.'
