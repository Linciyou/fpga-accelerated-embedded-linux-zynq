param(
    [Parameter(Mandatory = $true)]
    [int]$DiskNumber,
    [string]$ImagePath
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ImagePath)) {
    $ImagePath = Join-Path $PSScriptRoot "..\build\linux_images\sdcard.img"
}
$transcriptPath = Join-Path $PSScriptRoot "..\build\sd_verify.log"
Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
trap {
    Write-Error $_
    Stop-Transcript | Out-Null
    exit 1
}

$image = Get-Item -LiteralPath $ImagePath
$disk = Get-Disk -Number $DiskNumber

if ($disk.IsBoot -or $disk.IsSystem -or $disk.BusType -ne "USB") {
    throw "Refusing to read Disk ${DiskNumber}: it is not a non-system USB disk."
}
if ($disk.Size -lt $image.Length) {
    throw "Disk $DiskNumber is smaller than the image."
}

$source = [System.IO.File]::Open($image.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
$target = New-Object System.IO.FileStream("\\.\PhysicalDrive$DiskNumber", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite, 4194304, [System.IO.FileOptions]::SequentialScan)
try {
    $sourceBuffer = New-Object byte[] 4194304
    $targetBuffer = New-Object byte[] 4194304
    $offset = 0L

    while (($count = $source.Read($sourceBuffer, 0, $sourceBuffer.Length)) -gt 0) {
        $read = 0
        while ($read -lt $count) {
            $n = $target.Read($targetBuffer, $read, $count - $read)
            if ($n -eq 0) {
                throw "Unexpected end of Disk $DiskNumber at byte $($offset + $read)."
            }
            $read += $n
        }

        for ($i = 0; $i -lt $count; $i++) {
            if ($sourceBuffer[$i] -ne $targetBuffer[$i]) {
                throw "Verification failed at byte $($offset + $i)."
            }
        }
        $offset += $count
    }
}
finally {
    $target.Dispose()
    $source.Dispose()
}

Write-Output "Verified $offset bytes on Disk $DiskNumber."
Stop-Transcript | Out-Null
