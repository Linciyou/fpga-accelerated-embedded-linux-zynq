param(
    [string]$BoardAddress = "192.168.7.2",
    [int]$Port = 5000,
    [int]$TimeoutMilliseconds = 5000,
    [switch]$VerifyInternet
)

$ErrorActionPreference = "Stop"

function Invoke-ZynqCommand([string]$Command) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connection = $client.ConnectAsync($BoardAddress, $Port)
        if (-not $connection.Wait($TimeoutMilliseconds)) {
            throw "Timed out connecting to ${BoardAddress}:$Port."
        }
        $stream = $client.GetStream()
        $stream.ReadTimeout = $TimeoutMilliseconds
        $payload = [System.Text.Encoding]::ASCII.GetBytes("$Command`n")
        $stream.Write($payload, 0, $payload.Length)
        $buffer = New-Object byte[] 256
        $count = $stream.Read($buffer, 0, $buffer.Length)
        return [System.Text.Encoding]::ASCII.GetString($buffer, 0, $count).Trim()
    }
    finally {
        $client.Dispose()
    }
}

$ping = Invoke-ZynqCommand "PING"
if ($ping -ne "PONG") {
    throw "Unexpected board response: $ping"
}

if ($VerifyInternet) {
    $network = Invoke-ZynqCommand "NETCHECK"
    if ($network -ne "NET status=ok") {
        throw "Board Internet check failed: $network"
    }
}

$result = Invoke-ZynqCommand "RUN"
if ($result -notmatch '^RESULT status=0x[0-9a-fA-F]{8} bytes=4096 peak=1 ') {
    throw "FFT DMA test failed: $result"
}

Write-Output $result
