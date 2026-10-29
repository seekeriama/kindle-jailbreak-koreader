<#
.SYNOPSIS
    Automates the PC side of jailbreaking a Kindle with WinterBreak and installing KOReader.

.DESCRIPTION
    Run it twice, once per stage. Between stages you do the on-device steps the script prints.

      -Stage WinterBreak   Checks the Kindle's firmware, downloads WinterBreak from its official
                           GitHub release and copies it to the root of the Kindle.
      -Stage KOReader      Downloads the right KOReader build from its official GitHub release,
                           copies it to the Kindle and adds a launcher to the library.

    Every copied file is verified by SHA-256 hash. Nothing is re-hosted: all downloads come
    straight from the projects' own release pages.

.PARAMETER Stage
    WinterBreak or KOReader.

.PARAMETER DryRun
    Checks the Kindle and resolves download links, but downloads and copies nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-KindleJailbreak.ps1 -Stage WinterBreak
#>
param(
    [Parameter(Mandatory)][ValidateSet('WinterBreak', 'KOReader')][string]$Stage,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$WinterBreakUrl = 'https://github.com/KindleModding/WinterBreak/releases/latest/download/WinterBreak.tar.gz'
$KOReaderApi = 'https://api.github.com/repos/koreader/koreader/releases/latest'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Todo($lines) {
    Write-Host "`nNow on the Kindle:" -ForegroundColor Yellow
    $i = 1; foreach ($l in $lines) { Write-Host ("  {0}. {1}" -f $i, $l); $i++ }
}

# Firmware strings look like "Kindle 5.16.2.1.1 (409748 002)". Compare part by part,
# since [version] can't hold more than four parts.
function Compare-Firmware([string]$a, [string]$b) {
    $x = $a.Split('.') | ForEach-Object { [int]$_ }
    $y = $b.Split('.') | ForEach-Object { [int]$_ }
    for ($i = 0; $i -lt [math]::Max($x.Count, $y.Count); $i++) {
        $p = if ($i -lt $x.Count) { $x[$i] } else { 0 }
        $q = if ($i -lt $y.Count) { $y[$i] } else { 0 }
        if ($p -ne $q) { return [math]::Sign($p - $q) }
    }
    return 0
}

function Get-Kindle {
    $vols = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystemLabel -eq 'Kindle' })
    if ($vols.Count -eq 0) { throw 'No Kindle found. Plug it in by USB and make sure it shows up as a drive labelled "Kindle".' }
    if ($vols.Count -gt 1) { throw 'More than one drive is labelled "Kindle". Unplug the others and try again.' }
    $root = "$($vols[0].DriveLetter):\"
    $verFile = Join-Path $root 'system\version.txt'
    if (-not (Test-Path -LiteralPath $verFile)) { throw "Can't read $verFile, so the firmware version is unknown." }
    $raw = (Get-Content -LiteralPath $verFile -Raw).Trim()
    if ($raw -notmatch '(\d+(\.\d+)+)') { throw "Unrecognised firmware string: $raw" }
    [pscustomobject]@{
        Root     = $root
        Firmware = $Matches[1]
        FreeMB   = [math]::Round($vols[0].SizeRemaining / 1MB)
    }
}

function New-WorkDir([string]$name) {
    $d = Join-Path ([IO.Path]::GetTempPath()) ("kindle-jb-$name-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force (Join-Path $d 'download'), (Join-Path $d 'extracted') | Out-Null
    (Get-Item -LiteralPath $d).FullName
}

# Minimal .tar.gz extractor (ustar, GNU long names, pax paths). tar.exe fails on long
# paths, and this also refuses entries that would escape the destination folder.
function Expand-TarGz([string]$Archive, [string]$Dest) {
    $destFull = [IO.Path]::GetFullPath($Dest).TrimEnd('\') + '\'
    $fs = [IO.File]::OpenRead($Archive)
    $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress)
    $ms = New-Object IO.MemoryStream
    try { $gz.CopyTo($ms) } finally { $gz.Dispose(); $fs.Dispose() }
    $buf = $ms.ToArray()
    $str = { param($o, $n) $s = [Text.Encoding]::UTF8.GetString($buf, $o, $n); $i = $s.IndexOf([char]0); if ($i -ge 0) { $s.Substring(0, $i) } else { $s } }
    $pos = 0; $longName = $null
    while ($pos + 512 -le $buf.Length) {
        $name = & $str $pos 100
        if ($name -eq '') { break }
        $prefix = & $str ($pos + 345) 155
        if ($prefix) { $name = "$prefix/$name" }
        $sizeStr = (& $str ($pos + 124) 12).Trim()
        $size = if ($sizeStr) { [Convert]::ToInt64($sizeStr, 8) } else { 0 }
        $type = [char]$buf[$pos + 156]
        $data = $pos + 512
        $pos = $data + [math]::Ceiling($size / 512) * 512
        if ($type -eq 'L') { $longName = & $str $data $size; continue }
        if ($type -eq 'x') {
            foreach ($line in ([Text.Encoding]::UTF8.GetString($buf, $data, $size) -split "`n")) {
                if ($line -match '^\d+ path=(.*)$') { $longName = $Matches[1] }
            }
            continue
        }
        if ($type -eq 'g') { continue }
        if ($longName) { $name = $longName; $longName = $null }
        $rel = $name -replace '/', '\'
        if ($rel.StartsWith('.\')) { $rel = $rel.Substring(2) }
        if ($rel -eq '' -or $rel -eq '.') { continue }
        $target = [IO.Path]::GetFullPath((Join-Path $destFull $rel))
        if (-not $target.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe path in archive: $name" }
        if ($type -eq '5') { [IO.Directory]::CreateDirectory($target) | Out-Null }
        elseif ($type -eq '0' -or $type -eq [char]0) {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            $out = [IO.File]::Create($target); try { $out.Write($buf, $data, $size) } finally { $out.Dispose() }
        }
        else { Write-Warning "Skipped archive entry of type '$type': $name" }
    }
}

# Copies everything under $Src into $Dst (merging folders, empty ones included)
# and checks each file by hash. Returns the number of files copied.
function Copy-Verified([string]$Src, [string]$Dst) {
    $Src = (Get-Item -LiteralPath $Src).FullName.TrimEnd('\')
    $n = 0
    Get-ChildItem -LiteralPath $Src -Force -Recurse | ForEach-Object {
        $t = Join-Path $Dst $_.FullName.Substring($Src.Length + 1)
        if ($_.PSIsContainer) { New-Item -ItemType Directory -Force $t | Out-Null; return }
        New-Item -ItemType Directory -Force (Split-Path $t) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $t -Force
        if ((Get-FileHash -LiteralPath $t).Hash -ne (Get-FileHash -LiteralPath $_.FullName).Hash) { throw "Copy check failed: $t" }
        $n++
    }
    $n
}

$k = Get-Kindle
Write-Step "Kindle found at $($k.Root) - firmware $($k.Firmware), $($k.FreeMB) MB free"

if ($Stage -eq 'WinterBreak') {
    if ((Compare-Firmware $k.Firmware '5.18.1') -ge 0) {
        throw "Firmware $($k.Firmware) is 5.18.1 or newer. WinterBreak does not work on it. See https://kindlemodding.org for other options."
    }
    $bins = @(Get-ChildItem -LiteralPath $k.Root -Force -Filter '*.bin' -File)
    if ($bins) { Write-Warning ("Update files in the Kindle's root can install firmware updates. Delete them first: " + ($bins.Name -join ', ')) }

    if ($DryRun) { Write-Step "Dry run: would download $WinterBreakUrl and copy it to $($k.Root)"; return }

    Write-Step 'Downloading WinterBreak'
    $w = New-WorkDir 'winterbreak'
    $tgz = Join-Path $w 'download\WinterBreak.tar.gz'
    Invoke-WebRequest -Uri $WinterBreakUrl -OutFile $tgz -UseBasicParsing
    Expand-TarGz $tgz (Join-Path $w 'extracted')
    if (-not (Test-Path -LiteralPath (Join-Path $w 'extracted\.active_content_sandbox'))) { throw 'The WinterBreak download looks wrong (no .active_content_sandbox folder).' }

    Write-Step 'Copying WinterBreak to the Kindle'
    $n = Copy-Verified (Join-Path $w 'extracted') $k.Root
    Write-Host "Copied and verified $n files."

    Write-Todo @(
        'Safely eject the Kindle in Windows and unplug it.',
        'Open the Kindle Store (cart icon). When it asks to turn off Airplane Mode, tap Yes. The Kindle must be registered and on Wi-Fi.',
        'In the Mesquito screen that opens, tap WinterBreak.',
        'Wait about 30 seconds. Text should appear, then the home screen reloads. If no text appears, try again.',
        'Plug the Kindle back in and run this script with -Stage KOReader.'
    )
}
else {
    # KOReader's wiki: the "kindlehf" build is for firmware 5.16.3 and newer; PW2 and
    # newer touch Kindles on 5.16.2 or older use "kindlepw2".
    $flavor = if ((Compare-Firmware $k.Firmware '5.16.3') -ge 0) { 'kindlehf' } else { 'kindlepw2' }
    Write-Step "Looking up the latest KOReader release ($flavor build)"
    $rel = Invoke-RestMethod -Uri $KOReaderApi -UseBasicParsing
    $asset = $rel.assets | Where-Object { $_.name -match "^koreader-$flavor-.*\.zip$" } | Select-Object -First 1
    if (-not $asset) { throw "No koreader-$flavor zip in KOReader $($rel.tag_name)." }
    Write-Host "KOReader $($rel.tag_name): $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)"
    if ($k.FreeMB -lt 300) { throw "Only $($k.FreeMB) MB free on the Kindle. Free up at least 300 MB first." }

    if ($DryRun) { Write-Step "Dry run: would download $($asset.browser_download_url) and copy it to $($k.Root)"; return }

    $w = New-WorkDir 'koreader'
    $zip = Join-Path $w "download\$($asset.name)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $w 'extracted') -Force
    if (-not (Test-Path -LiteralPath (Join-Path $w 'extracted\koreader\koreader.sh'))) { throw 'The KOReader download looks wrong (no koreader\koreader.sh).' }

    Write-Step 'Copying KOReader to the Kindle (this takes a minute)'
    $n = Copy-Verified (Join-Path $w 'extracted') $k.Root
    Write-Host "Copied and verified $n files."

    # WinterBreak runs any .sh in documents as a "scriptlet" that shows up like a book.
    # It must use LF line endings, or the Kindle's shell can't run it.
    Write-Step 'Adding the KOReader launcher to the library'
    $launcher = Join-Path $PSScriptRoot 'launcher\KOReader.sh'
    $text = ([IO.File]::ReadAllText($launcher)) -replace "`r`n", "`n"
    [IO.File]::WriteAllText((Join-Path $k.Root 'documents\KOReader.sh'), $text, (New-Object Text.UTF8Encoding($false)))

    Write-Todo @(
        'Safely eject the Kindle in Windows and unplug it.',
        'Find the "KOReader" item in your library (sort by Recent if needed) and tap it.',
        'KOReader opens after a few seconds. To go back to the normal Kindle screen, use KOReader''s menu > Exit.'
    )
}

Write-Host "`nDone." -ForegroundColor Green
