#requires -Version 3 -module Ravello

# Script will import a VM from a vSphere environment
# into your Ravello Image library
#
 
param(
    [Parameter(Mandatory=$true)]
    [string]$VmName,
    [Parameter(Mandatory=$true)]
    [string]$VMHost,
    [Parameter(Mandatory=$true)]
    [string]$EsxUser,
    [Parameter(Mandatory=$true)]
    [string]$EsxPassword
)

$PCLI = 'VMware.VimAutomation.Core'

# Load PowerCLI
Try
{
    Get-PSSnapin -Name $PCLI -ErrorAction Stop | Out-Null
}
Catch
{
    Add-PSSnapin -Name $PCLI
}

# Get credentials
$sEsxPswd = ConvertTo-SecureString -String $EsxPassword -AsPlainText -Force
$credEsx = New-Object System.Management.Automation.PSCredential ($EsxUser, $sEsxPswd)

Connect-VIServer -Server $VMHost -Credential $credEsx | Out-Null

# Get VMX path
$vm = Get-VM -Name $vmName
while($vm.PowerState -ne 'PoweredOff')
{
    Stop-VM -VM $vm -Confirm:$false
    sleep 5
}

# Remove existing Image
$img = Get-RavelloImage -ImageName $vmName
if($img)
{
    $img | Remove-RavelloImage -Confirm:$false
}

# Import VM
$sImport = @{
    EsxVmPath = $vm.ExtensionData.Config.Files.VmPathName
    EsxCredential = $credEsx
    EsxServer = $vm.ExtensionData.VMHost.Name
    Confirm = $false
}
Import-Ravello @sImport

Disconnect-VIServer -Server $VMHost -Confirm:$false

# Set VM as verified
$flag = '1stPass'
while('1stPass','PARSING' -contains $flag)
{
    $img = Get-RavelloImage -ImageName $vmName
    $flag = $img.loadingStatus
}

if($img.loadingStatus -ne 'DONE')
{
    $img | Update-RavelloImage -Description 'Imported from vSphere' -Confirm:$false
}
