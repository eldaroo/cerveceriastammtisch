param(
    [string]$SourcePath = "cerveceria.sql",
    [string]$OutputSql = "nomad\\dist\\db-init\\01-restore.sql"
)

$sourcePath = Resolve-Path $SourcePath
$outputPath = Join-Path (Get-Location) $OutputSql
$outputDir = Split-Path -Parent $outputPath

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

if ([System.IO.Path]::GetExtension($sourcePath) -eq ".gz") {
    $inputStream = [System.IO.File]::OpenRead($sourcePath)
    $gzipStream = New-Object System.IO.Compression.GzipStream(
        $inputStream,
        [System.IO.Compression.CompressionMode]::Decompress
    )
    $outputStream = [System.IO.File]::Create($outputPath)

    try {
        $buffer = New-Object byte[] 8192
        while (($read = $gzipStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $read)
        }
    }
    finally {
        $outputStream.Dispose()
        $gzipStream.Dispose()
        $inputStream.Dispose()
    }
}
else {
    Copy-Item -LiteralPath $sourcePath -Destination $outputPath -Force
}

$size = (Get-Item $outputPath).Length
Write-Output "SQL generado en: $outputPath"
Write-Output "Tamano generado: $size bytes"

if ($size -lt 50000) {
    Write-Warning "El SQL extraido parece demasiado chico. Revisa si el backup de base de datos esta incompleto antes de restaurar."
}
