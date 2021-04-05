Param (
    [Parameter(Mandatory=$true)]
    [string]$VHDX_Zip,
    [string]$SwitchName = "EdgeSwitch"
)

$files = Get-ChildItem .\output\

if ((Get-VMSwitch | Where-Object { $_.Name -eq $SwitchName }).Count -eq 0 ) {
        
    Write-Host "Creating VMSwitch: $SwitchName..."
    New-VMSwitch $SwitchName -SwitchType Internal 

} else {
    Write-Host "VMSitch $SwitchName already exists, skipping switch creation."
}

if ((Get-NetIPAddress | Where-Object { $_.IPAddress -eq "172.17.1.1" } | Measure-Object).Count -eq 0 ) {
    Write-Host "Creating Net IP..."
    New-NetIPAddress -IPAddress 172.17.1.1 -PrefixLength 24 -InterfaceAlias "vEthernet ($SwitchName)"

} else {
    Write-Host "NetIPAddress 172.17.1.1 already exists, skipping net ip creation."
}

if ((Get-NetNat | Where-Object { $_.Name -eq "EdgeNAT"}).Count -eq 0 ) {
    Write-Host "Creating NAT..."
    New-NetNat -Name EdgeNAT -InternalIPInterfaceAddressPrefix 172.17.1.0/24

} else {
    Write-Host "EdgeNAT already exists, skipping NAT creation."
}


foreach ($file in $files) {

    $iso = ".\output\" + $file.Name
    $vmname = $file.Basename
    $vhdx = "$vmname.vhdx"
    
    if ((Test-Path $vhdx)) {
        Write-Error "$vhdx already exists. Exiting. Please delete all existing vhdx files before rerunning script"
        exit 1
    }

    Write-Host "*******************************************"
    Write-Host "Setting up $vmname node."
    
    if (!(Test-Path $vhdx)) {

        Write-Host "Extracting VHDX for $vmname..."
        Expand-Archive -LiteralPath $VHDX_Zip -DestinationPath .
    
        Rename-Item -Path ".\$((Get-Item $VHDX_Zip).Basename)" -NewName "$vhdx"
    }

    Write-Host "Creating $vmname VM with 1GB starting memory, 2 processors and iso: $iso..."

    New-VM -Name $vmname -MemoryStartupBytes 1GB -VHDPath .\$vhdx
    Set-VMProcessor -VMName $vmname -Count 2
    Connect-VMNetworkAdapter -VMName $vmname -Name "Network Adapter" -SwitchName $SwitchName
    Set-VMDvdDrive -VMName $vmname -Path $iso 

    Write-Host "Starting VM..."
    Start-VM $vmname
    Write-Host "*******************************************"
}