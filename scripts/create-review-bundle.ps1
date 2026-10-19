param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Phase
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail {
    param([string]$Message)
    throw "[Review Bundle] $Message"
}

function Get-NormalizedRelativePath {
    param([string]$Path)

    $normalized = $Path -replace '\\', '/'
    $normalized = $normalized -replace '^\./', ''
    return $normalized
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)

    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relative = [System.Uri]::UnescapeDataString($relativeUri.ToString())

    return ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Test-ProhibitedPath {
    param([string]$RelativePath)

    $p = (Get-NormalizedRelativePath $RelativePath).ToLowerInvariant()
    $segments = $p -split '/'

    if ($p -eq '.env' -or $p -like '.env.*' -or $p -like '*/.env' -or $p -like '*/.env.*') {
        return $true
    }

    if ($p -match '(^|/)\.git(/|$)') { return $true }
    if ($p -match '(^|/)node_modules(/|$)') { return $true }
    if ($p -match '(^|/)\.svelte-kit(/|$)') { return $true }
    if ($p -match '(^|/)build(/|$)') { return $true }
    if ($p -match '(^|/)\.review(/|$)') { return $true }

    foreach ($segment in $segments) {
        if ($segment -in @('secrets', 'credentials', 'tokens', 'cookies')) {
            return $true
        }
    }

    if ($p -match '\.(pem|key|dump|backup)$') { return $true }

    return $false
}

function Assert-PathInsideRepo {
    param(
        [string]$RepoRoot,
        [string]$FullPath
    )

    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath($FullPath)
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar

    if ($full -ne $root -and -not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "Caminho fora do repositório detetado: $FullPath"
    }
}

function Assert-NoReparsePointInPath {
    param(
        [string]$RepoRoot,
        [string]$FullPath
    )

    Assert-PathInsideRepo -RepoRoot $RepoRoot -FullPath $FullPath

    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath($FullPath)
    $relative = Get-RelativePathCompat -BasePath $root -TargetPath $full

    $current = $root
    foreach ($part in ($relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($part) -or $part -eq '.') {
            continue
        }

        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Fail "Symlink/junction/reparse point não permitido no bundle: $relative"
            }
        }
    }
}

function Remove-ReviewPathSafely {
    param(
        [string]$ReviewRoot,
        [string]$Target
    )

    $reviewFull = [System.IO.Path]::GetFullPath($ReviewRoot).TrimEnd('\', '/')
    $targetFull = [System.IO.Path]::GetFullPath($Target)
    $prefix = $reviewFull + [System.IO.Path]::DirectorySeparatorChar

    if (-not $targetFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "Recusada limpeza fora de .review/: $targetFull"
    }

    if ($targetFull -eq $reviewFull) {
        Fail "Recusada tentativa de apagar a raiz .review/."
    }

    if (Test-Path -LiteralPath $targetFull) {
        Remove-Item -LiteralPath $targetFull -Recurse -Force
    }
}

function Write-Utf8File {
    param(
        [string]$Path,
        [object[]]$Lines
    )

    $stringLines = @()
    foreach ($line in $Lines) {
        if ($null -eq $line) {
            $stringLines += ''
        } else {
            $stringLines += [string]$line
        }
    }

    $content = if ($stringLines.Count -gt 0) {
        ($stringLines -join [Environment]::NewLine) + [Environment]::NewLine
    } else {
        ''
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $content,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Fail "Git não foi encontrado no PATH."
}

$repoRootRaw = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $repoRootRaw) {
    Fail "Executa este script dentro de um repositório Git."
}

$RepoRoot = [System.IO.Path]::GetFullPath(($repoRootRaw | Select-Object -First 1).Trim())
Push-Location $RepoRoot

try {
    $SafePhase = ($Phase.Trim() -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($SafePhase)) {
        Fail "O identificador da fase não produz um nome de ficheiro válido."
    }

    $Head = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $Head) {
        Fail "Não foi possível obter o HEAD atual."
    }

    $StatusLines = @(& git status --short)
    if ($LASTEXITCODE -ne 0) {
        Fail "Falhou 'git status --short'."
    }

    $LogLines = @(& git log -6 --oneline)
    if ($LASTEXITCODE -ne 0) {
        Fail "Falhou 'git log -6 --oneline'."
    }

    $TrackedLines = @(& git -c core.quotepath=false diff --name-status --no-renames HEAD --)
    if ($LASTEXITCODE -ne 0) {
        Fail "Não foi possível obter as alterações tracked contra HEAD."
    }

    $UntrackedPaths = @(& git -c core.quotepath=false ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        Fail "Não foi possível obter os ficheiros untracked."
    }

    $Changes = New-Object System.Collections.Generic.List[object]
    $Seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($line in $TrackedLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) {
            Fail "Estado Git inesperado: $line"
        }

        $gitStatus = $parts[0].Trim()
        $path = Get-NormalizedRelativePath $parts[1]

        $state = switch -Regex ($gitStatus) {
            '^A' { 'added'; break }
            '^D' { 'deleted'; break }
            default { 'modified' }
        }

        if ($Seen.Add($path)) {
            $Changes.Add([pscustomobject]@{
                Path = $path
                State = $state
            })
        }
    }

    foreach ($pathRaw in $UntrackedPaths) {
        if ([string]::IsNullOrWhiteSpace($pathRaw)) { continue }

        $path = Get-NormalizedRelativePath $pathRaw
        if ($Seen.Add($path)) {
            $Changes.Add([pscustomobject]@{
                Path = $path
                State = 'added'
            })
        }
    }

    foreach ($change in $Changes) {
        if (Test-ProhibitedPath $change.Path) {
            Fail "Caminho proibido detetado nas alterações: $($change.Path)"
        }
    }

    $HandoffSource = Join-Path $RepoRoot 'codex-handoff.md'
    if (-not (Test-Path -LiteralPath $HandoffSource -PathType Leaf)) {
        Fail "Falta 'codex-handoff.md' na raiz. Atualiza o handoff antes de gerar o bundle."
    }

    Assert-NoReparsePointInPath -RepoRoot $RepoRoot -FullPath $HandoffSource

    $HandoffText = [System.IO.File]::ReadAllText($HandoffSource, [System.Text.Encoding]::UTF8)
    if (
        $HandoffText.IndexOf($Phase, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and
        $HandoffText.IndexOf($SafePhase, [System.StringComparison]::OrdinalIgnoreCase) -lt 0
    ) {
        Write-Warning "codex-handoff.md não menciona a fase '$Phase'. Confirma que o handoff foi atualizado para esta tarefa."
    }

    $ReviewRoot = Join-Path $RepoRoot '.review'
    if (-not (Test-Path -LiteralPath $ReviewRoot)) {
        New-Item -ItemType Directory -Path $ReviewRoot | Out-Null
    }

    Assert-PathInsideRepo -RepoRoot $RepoRoot -FullPath $ReviewRoot

    $StagingRoot = Join-Path $ReviewRoot (".staging-{0}-{1}" -f $SafePhase, $PID)
    $ZipPath = Join-Path $ReviewRoot ("deepmap-{0}-review.zip" -f $SafePhase)

    if (Test-Path -LiteralPath $StagingRoot) {
        Remove-ReviewPathSafely -ReviewRoot $ReviewRoot -Target $StagingRoot
    }

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-ReviewPathSafely -ReviewRoot $ReviewRoot -Target $ZipPath
    }

    New-Item -ItemType Directory -Path $StagingRoot | Out-Null
    $ReviewMetaDir = Join-Path $StagingRoot 'review'
    New-Item -ItemType Directory -Path $ReviewMetaDir | Out-Null

    try {
        Copy-Item -LiteralPath $HandoffSource -Destination (Join-Path $ReviewMetaDir 'codex-handoff.md')

        $PatchPath = Join-Path $ReviewMetaDir 'changes.patch'
        & git diff --binary "--output=$PatchPath" HEAD --
        if ($LASTEXITCODE -ne 0) {
            Fail "Falhou a geração de review/changes.patch."
        }

        Write-Utf8File -Path (Join-Path $ReviewMetaDir 'git-status.txt') -Lines $StatusLines
        Write-Utf8File -Path (Join-Path $ReviewMetaDir 'git-log.txt') -Lines $LogLines

        $ManifestEntries = New-Object System.Collections.Generic.List[object]
        $Deleted = New-Object System.Collections.Generic.List[string]

        foreach ($change in ($Changes | Sort-Object Path)) {
            if ($change.State -eq 'deleted') {
                $Deleted.Add($change.Path)
                $ManifestEntries.Add([pscustomobject]@{
                    Path = $change.Path
                    State = 'deleted'
                    Sha256 = '-'
                })
                continue
            }

            $sourcePath = Join-Path $RepoRoot ($change.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                Fail "O ficheiro final esperado não existe: $($change.Path)"
            }

            Assert-NoReparsePointInPath -RepoRoot $RepoRoot -FullPath $sourcePath

            $destinationPath = Join-Path $StagingRoot ($change.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $destinationDir = Split-Path -Parent $destinationPath
            if (-not (Test-Path -LiteralPath $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }

            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath

            $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $copiedHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash.ToLowerInvariant()

            if ($sourceHash -ne $copiedHash) {
                Fail "SHA-256 não coincide após copiar: $($change.Path)"
            }

            $ManifestEntries.Add([pscustomobject]@{
                Path = $change.Path
                State = $change.State
                Sha256 = $sourceHash
            })
        }

        $ManifestLines = New-Object System.Collections.Generic.List[string]
        $ManifestLines.Add("DeepMap Review Bundle")
        $ManifestLines.Add("phase: $Phase")
        $ManifestLines.Add("safe_phase: $SafePhase")
        $ManifestLines.Add("base_head: $Head")
        $ManifestLines.Add("generated_utc: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
        $ManifestLines.Add("")
        $ManifestLines.Add("[files]")

        if ($ManifestEntries.Count -eq 0) {
            $ManifestLines.Add("(no working-tree product changes detected)")
        } else {
            foreach ($entry in $ManifestEntries) {
                $ManifestLines.Add("$($entry.State)`t$($entry.Sha256)`t$($entry.Path)")
            }
        }

        $ManifestLines.Add("")
        $ManifestLines.Add("[deleted]")
        if ($Deleted.Count -eq 0) {
            $ManifestLines.Add("(none)")
        } else {
            foreach ($path in $Deleted) {
                $ManifestLines.Add($path)
            }
        }

        $ManifestLines.Add("")
        $ManifestLines.Add("[review metadata]")
        $ManifestLines.Add("review/codex-handoff.md")
        $ManifestLines.Add("review/changes.patch")
        $ManifestLines.Add("review/manifest.txt")
        $ManifestLines.Add("review/git-status.txt")
        $ManifestLines.Add("review/git-log.txt")
        $ManifestLines.Add("")
        $ManifestLines.Add("[temporary / not product]")
        $ManifestLines.Add("codex-handoff.md")
        $ManifestLines.Add(".review/")

        $ManifestPath = Join-Path $ReviewMetaDir 'manifest.txt'
        Write-Utf8File -Path $ManifestPath -Lines $ManifestLines

        $ExpectedZipEntries = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $StagingHashes = @{}

        foreach ($file in Get-ChildItem -LiteralPath $StagingRoot -File -Recurse -Force) {
            $relativeRaw = Get-RelativePathCompat -BasePath $StagingRoot -TargetPath $file.FullName
            $relative = Get-NormalizedRelativePath $relativeRaw

            if (Test-ProhibitedPath $relative) {
                Fail "Ficheiro proibido detetado na staging: $relative"
            }

            Assert-NoReparsePointInPath -RepoRoot $RepoRoot -FullPath $file.FullName

            [void]$ExpectedZipEntries.Add($relative)
            $StagingHashes[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }

        Compress-Archive -Path (Join-Path $StagingRoot '*') -DestinationPath $ZipPath -CompressionLevel Optimal

        if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
            Fail "O ZIP não foi criado."
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            $ActualZipEntries = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($entry in $archive.Entries) {
                if ([string]::IsNullOrEmpty($entry.Name)) { continue }

                $entryPath = Get-NormalizedRelativePath $entry.FullName
                if (Test-ProhibitedPath $entryPath) {
                    Fail "O ZIP contém um caminho proibido: $entryPath"
                }

                [void]$ActualZipEntries.Add($entryPath)

                if (-not $StagingHashes.ContainsKey($entryPath)) {
                    Fail "Entrada inesperada no ZIP: $entryPath"
                }

                $sha = [System.Security.Cryptography.SHA256]::Create()
                try {
                    $entryStream = $entry.Open()
                    try {
                        $hashBytes = $sha.ComputeHash($entryStream)
                    }
                    finally {
                        $entryStream.Dispose()
                    }
                }
                finally {
                    $sha.Dispose()
                }

                $entryHash = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
                if ($entryHash -ne $StagingHashes[$entryPath]) {
                    Fail "SHA-256 do conteúdo do ZIP não coincide: $entryPath"
                }
            }

            foreach ($expected in $ExpectedZipEntries) {
                if (-not $ActualZipEntries.Contains($expected)) {
                    Fail "Falta no ZIP: $expected"
                }
            }

            foreach ($actual in $ActualZipEntries) {
                if (-not $ExpectedZipEntries.Contains($actual)) {
                    Fail "Entrada inesperada no ZIP: $actual"
                }
            }
        }
        finally {
            $archive.Dispose()
        }

        foreach ($entry in $ManifestEntries) {
            if ($entry.State -eq 'deleted') { continue }

            $copiedPath = Join-Path $StagingRoot ($entry.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $hash = (Get-FileHash -LiteralPath $copiedPath -Algorithm SHA256).Hash.ToLowerInvariant()

            if ($hash -ne $entry.Sha256) {
                Fail "Falhou validação final de SHA-256: $($entry.Path)"
            }
        }

        Write-Host ""
        Write-Host "Review Bundle criado e validado:"
        Write-Host $ZipPath
        Write-Host ""
        Write-Host "Base HEAD: $Head"
        Write-Host "Ficheiros alterados detetados: $($Changes.Count)"
        Write-Host "Nenhum commit, stage, push, deploy ou migration remota foi executado."
    }
    finally {
        if (Test-Path -LiteralPath $StagingRoot) {
            Remove-ReviewPathSafely -ReviewRoot $ReviewRoot -Target $StagingRoot
        }
    }
}
finally {
    Pop-Location
}
