[CmdletBinding()]
param(
    [string]$ExpectedArchiveHash = "9AE06720AA52DD29900AE0C3ABEABD1751DB62B2DD13173DBA7541BD2B139E9D"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$archivePath = Join-Path $repositoryRoot "Releases\Moonlit-iOS-v0.1.zip"
$forbiddenExtensions = @(
    ".p8", ".p12", ".pfx", ".pem", ".key", ".cer", ".mobileprovision", ".provisionprofile"
)
$secretPatterns = @(
    "-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    "\bgh[pousr]_[A-Za-z0-9]{30,}\b",
    "\bsb_secret_[A-Za-z0-9_-]{20,}\b",
    "\beyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b"
)

if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "Missing release archive: $archivePath"
}

$actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
if ($actualHash -ne $ExpectedArchiveHash) {
    throw "Release archive hash does not match the documented v0.1 archive."
}

$trackedFiles = @(& git -C $repositoryRoot ls-files)
if ($LASTEXITCODE -ne 0) { throw "Could not read the Git index." }

$unsafeTrackedNames = @($trackedFiles | Where-Object {
    $extension = [IO.Path]::GetExtension($_).ToLowerInvariant()
    $forbiddenExtensions -contains $extension -or $_ -match "(^|/)(\.env|Supabase\.local\.xcconfig)$"
})
if ($unsafeTrackedNames.Count -gt 0) {
    throw "Git tracks forbidden local configuration or signing files: $($unsafeTrackedNames -join ', ')"
}

$matchedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($relativePath in $trackedFiles) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf) -or $relativePath.EndsWith(".zip")) { continue }
    $content = [IO.File]::ReadAllText($fullPath)
    foreach ($pattern in $secretPatterns) {
        if ($content -match $pattern) { [void]$matchedFiles.Add($relativePath) }
    }
}
if ($matchedFiles.Count -gt 0) {
    throw "Potential credential material found in tracked files: $([string]::Join(', ', $matchedFiles))"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $unsafeEntries = @($archive.Entries | Where-Object {
        $extension = [IO.Path]::GetExtension($_.FullName).ToLowerInvariant()
        $forbiddenExtensions -contains $extension -or $_.FullName -match "(^|/)(\.env|Supabase\.local\.xcconfig)$"
    })
    if ($unsafeEntries.Count -gt 0) {
        throw "Release archive contains forbidden credential or signing filenames."
    }

    foreach ($entry in $archive.Entries) {
        if ($entry.Length -eq 0 -or $entry.Length -gt 2MB) { continue }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
        foreach ($pattern in $secretPatterns) {
            if ($content -match $pattern) {
                throw "Potential credential material found in release archive entry: $($entry.FullName)"
            }
        }
    }
} finally {
    $archive.Dispose()
}

Write-Host "Release archive, tracked filenames, and tracked text passed the credential/signing scan."
