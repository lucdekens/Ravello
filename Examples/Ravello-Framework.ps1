# Framework to work with the Ravello module

#region Start
$workDomain = 'work.domain'
$workProxy = 'http://proxy.work.domain:8080'
$workCredentials = "$($env:USERPROFILE)\workRavelloCreds.csv"
$homeCredentials = "$($env:USERPROFILE)\homeRavelloCreds.csv"

# Work
if($env:USERDOMAIN -match $workDomain){
  $obj = Import-Csv -Path $workCredentials -UseCulture
  $sPswd = ConvertTo-SecureString -String $obj.Pswd -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential ($obj.User, $sPswd)
  $connect = Connect-Ravello -Credential $cred -Proxy $workProxy
}
# Home
else{
  $obj = Import-Csv -Path $homeCredentials -UseCulture
  $sPswd = ConvertTo-SecureString -String $obj.Pswd -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential ($obj.User, $sPswd)
  $connect = Connect-Ravello -Credential $cred
}
#endregion

#region Your Ravello Automation Script

#endregion

#region Stop
Disconnect-Ravello -Confirm:$false
#endregion