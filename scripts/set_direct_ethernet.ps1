param(
    [Parameter(Mandatory = $true)]
    [string]$InterfaceAlias,
    [string]$HostAddress = "192.168.7.1",
    [int]$PrefixLength = 24
)

$ErrorActionPreference = "Stop"
$adapter = Get-NetAdapter -Name $InterfaceAlias
if ($adapter.Status -eq "Disabled") {
    Enable-NetAdapter -Name $InterfaceAlias -Confirm:$false
}

$addresses = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" }
$linkLocal = $addresses | Where-Object { $_.IPAddress -like "169.254.*" }
$conflicts = $addresses | Where-Object {
    $_.IPAddress -ne $HostAddress -and $_.IPAddress -notlike "169.254.*"
}
if ($conflicts) {
    throw "'$InterfaceAlias' already has IPv4 address(es): $($conflicts.IPAddress -join ', '). Refusing to replace them."
}

Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Dhcp Disabled
foreach ($address in $linkLocal) {
    Remove-NetIPAddress -InputObject $address -Confirm:$false
}
if (-not ($addresses | Where-Object { $_.IPAddress -eq $HostAddress })) {
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $HostAddress -PrefixLength $PrefixLength |
        Out-Null
}

Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 |
    Select-Object IPAddress,PrefixLength,InterfaceAlias
