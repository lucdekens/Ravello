# Check if VMs with Public IP in affected regions
$maintInfo = @"
Cloud,Region
Google Cloud,us-central1
Amazon,Oregon
"@

Write-Output "`r==> Checking affected public IPs"
foreach($app in Get-RavelloApplication){
    foreach($cloud in ($maintInfo | ConvertFrom-Csv)){
        if($cloud.Cloud -eq $app.deployment.cloud -and $cloud.Region -eq $app.deployment.regionName){
            foreach($vm in Get-RavelloApplicationVm -ApplicationId $app.id){
                $vm.networkConnections | where{$_.ipConfig.hasPublicIp} | %{
                    Write-Output "$($cloud.Cloud)/$($cloud.Region)/$($app.name)/$($vm.name)"
                }
            }
        }
    }
}

# Check if any with affected Elastic IP
$eipInfo = @('US-West')
Write-Output "`r==> Checking affected public IPs"
Get-RavelloElasticIP | where{$eipInfo -contains $_.Location} |
Select ownerAppName,ownerVmName,ip
