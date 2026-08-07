param(
    [Parameter(Mandatory = $true)]
    [int]$DiskNumber,
    [string]$ImagePath
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ImagePath)) {
    $ImagePath = Join-Path $PSScriptRoot "..\build\linux_images\sdcard.img"
}
$transcriptPath = Join-Path $PSScriptRoot "..\build\sd_write.log"
Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
trap {
    Write-Error $_
    Stop-Transcript | Out-Null
    exit 1
}

$image = Get-Item -LiteralPath $ImagePath
$disk = Get-Disk -Number $DiskNumber

if ($disk.IsBoot -or $disk.IsSystem -or $disk.BusType -ne "USB") {
    throw "Refusing to write Disk ${DiskNumber}: it is not a non-system USB disk."
}
if ($disk.Size -lt $image.Length) {
    throw "Disk $DiskNumber is smaller than the image."
}

$madeOffline = $false
try {
    if (-not $disk.IsOffline) {
        try {
            Set-Disk -Number $DiskNumber -IsOffline $true -ErrorAction Stop
            $madeOffline = $true
        }
        catch {
            # Windows cannot offline some removable readers. Clearing the
            # already-validated target releases its mounted partitions.
            Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
        }
    }

    $source = [System.IO.File]::Open($image.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $target = New-Object System.IO.FileStream("\\.\PhysicalDrive$DiskNumber", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4194304, [System.IO.FileOptions]::WriteThrough)
    try {
        $buffer = New-Object byte[] 4194304
        while (($count = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $target.Write($buffer, 0, $count)
        }
        $target.Flush($true)
    }
    finally {
        if ($target) { $target.Dispose() }
        if ($source) { $source.Dispose() }
    }
}
finally {
    if ($madeOffline) {
        Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction Stop
    }
    Update-Disk -Number $DiskNumber -ErrorAction Stop
}

Write-Output "Wrote $($image.Length) bytes to Disk $DiskNumber."
Stop-Transcript | Out-Null
