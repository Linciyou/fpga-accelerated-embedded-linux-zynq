param(
    [string]$BoardAddress = "192.168.7.2",
    [int]$Port = 5000,
    [int]$TimeoutMilliseconds = 120000
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
        $buffer = New-Object byte[] 1024
        $count = $stream.Read($buffer, 0, $buffer.Length)
        return [System.Text.Encoding]::ASCII.GetString($buffer, 0, $count).Trim()
    }
    finally {
        $client.Dispose()
    }
}

if ((Invoke-ZynqCommand "PING") -ne "PONG") {
    throw "Board did not return PONG."
}

foreach ($iterations in 1000, 10000) {
    $result = Invoke-ZynqCommand "BENCH $iterations"
    if ($result -notmatch "^DMAENGINE_BENCH iterations=$iterations ok=$iterations failed=0 " -or
        $result -notmatch "timeouts=0" -or $result -notmatch "dma_errors=0" -or
        $result -notmatch "validation_errors=0") {
        throw "DMAengine stress test failed: $result"
    }
    Write-Output $result
}
