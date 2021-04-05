Param (
    [switch]$Network,
    [string]$SwitchName = "EdgeSwitch"
)


$files = Get-ChildItem .\output\

foreach ($file in $files) {

    $vmname = $file.Basename
    $vhdx = "$vmname.vhdx"

    if(Get-VM -Name $vmname){
        Write-Output "Cleaning up VM: $vmname"
        Stop-VM $vmname
        Remove-VM $vmname -Force
        Remove-Item $vhdx -Force
    } 
}
if($Network){
    Write-Output "Cleaning up network..."
    Remove-NetNat -name EdgeNat -Confirm:$false
    Remove-VMSwitch -Name "EdgeNAT" -Force
}
