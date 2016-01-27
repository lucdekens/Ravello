#requires -Version 3 -module Ravello

# Script will check the status of the VNC and RDP connection to a VM running
# in a Ravello application
# 
param(
    [Parameter(Mandatory=$true)]
    [string]$ApplicationName,
    [Parameter(Mandatory=$true)]
    [string[]]$VmNames,
    [DateTime]$Finish = (Get-Date).AddMinutes(5)
)

function Get-VncStatus
{
  param(
    [string]$VncUri
  )   
  Process
  {
    $web = Invoke-WebRequest -Uri $VncUri
    if($web)
    {
      if($web.StatusCode -eq 200){'OK'}
      else{$web.StatusCode}
    }
    else{'No VNC'}
  }
}

function Get-RDPStatus
{
  param(
    [PSObject]$VM
  )

  process
  {
    Write-Verbose -Message $VM.externalFqdn
    $port = 3389
    $rdp = $VM.suppliedServices | Where-Object -FilterScript {$_.protocol -eq 'RDP'}
    if($rdp.externalPort)
    {
        $port = $rdp.externalport
    }
    Try {$netDns = [System.Net.Dns]::GetHostAddresses($VM.externalFqdn)}
    catch [Exception] {return 'No DNS'}
    Try
    {
      $netPort = New-Object System.Net.Sockets.TCPClient -ArgumentList $VM.externalFqdn, $port
      $netPort.Close()
      'OK'
    }
    Catch{'No RDP'}
  }
}

$report = @()

while((Get-Date) -le $Finish)
{
  $obj = [ordered]@{
    Time      = Get-Date -Format 'hh:mm:ss'
  }
  $i = 1
  foreach($vmName in $VmNames){
    $vm = Get-RavelloApplicationVm -ApplicationName $ApplicationName -VmName $vmName -Deployment
    $obj.Add("VM$($i)",$vmName)
    $obj.Add("VM$($i)Dns",$vm.externalFqdn)
    $obj.Add("VM$($i)State",$vm.state)
    $vncStatus = &{
      $uri = Get-RavelloApplicationVmVnc -ApplicationName $ApplicationName -VmName $VmName
      if($uri)
      {Get-VncStatus -VncUri $uri}
      else
      {'No NVC Uri'}}
    $obj.Add("VM$($i)VNC",$vncStatus)
    $rdpStatus = &{Get-RDPStatus -VM $vm}
    $obj.Add("VM$($i)RDP",$rdpStatus)
    $i++
  }

  $row = New-Object -TypeName PSObject -Property $obj
  $report += $row
  $row

  Start-Sleep -Seconds 15
}
