#requires -Version 3
#region Module variables
$RavelloBaseUrl = 'https://cloud.ravellosystems.com/api/v1'
#endregion

#region Helpers
# .ExternalHelp Ravello-Help.xml
function ConvertFrom-hRavelloJsonDateTime
{
  [CmdletBinding()]
  param (
    [int64]$DateTime
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    (New-Object -TypeName DateTime -ArgumentList (1970, 1, 1, 0, 0, 0, 0)).AddMilliseconds([long]$DateTime).ToLocalTime()
  }
}

# .ExternalHelp Ravello-Help.xml
function ConvertTo-hRavelloJsonDateTime
{
  [CmdletBinding()]
  param (
    [DateTime]$Date
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    [int64]($Date.ToUniversalTime() - (Get-Date -Date '1/1/1970')).totalmilliseconds
  }
}

# .ExternalHelp Ravello-Help.xml
function Convert-hRavelloTimeField
{
  param(
    [psobject[]]$Object
  )
  
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    foreach($obj in $Object)
    {
      $obj.psobject.properties | ForEach-Object -Process {
        if('System.Object[]', 'System.Management.Automation.PSCustomObject' -contains $_.TypeNameOfValue)
        {Convert-hRavelloTimeField -Object $obj.$($_.Name)}
        elseif($_.Name -match 'Time' -and $_.TypeNameOfValue -eq 'System.Int64')
        {$obj.$($_.Name) = (ConvertFrom-hRavelloJsonDateTime -DateTime $obj.$($_.Name))}
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Invoke-hRavelloRest
{
  [CmdletBinding()]
  param (
    [String]$Method,
    [String]$Request,
    [PSObject]$Body
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
		
    $headers = $Script:AuthHeader.Clone()
    $headers.Add('Accept', 'application/json')
    $sRest = @{
      Uri         = $RavelloBaseUrl, $Request -join '/'
      Method      = $Method
      ContentType = 'application/json'
      Headers     = $local:headers
      ErrorAction = 'Stop'
    }
    if (Get-Process -Name fiddler -ErrorAction SilentlyContinue)
    {$sRest.Add('Proxy', 'http://127.0.0.1:8888')}
    if ($Script:RavelloSession)
    {$sRest.Add('WebSession', $Script:RavelloSession)}
    else
    {$sRest.Add('SessionVariable', 'Script:RavelloSession')}
    # To handle nested properties the Depth parameter is used explicitely (default is 2)
    if ($Body)
    {$sRest.Add('Body', ($Body | ConvertTo-Json -Depth 32 -Compress))}
		
    Write-Debug -Message "`tUri             : $($sRest.Uri)"
    Write-Debug -Message "`tMethod          : $($sRest.Method)"
    Write-Debug -Message "`tContentType     : $($sRest.ContentType)"
    Write-Debug -Message "`tHeaders"
    $sRest.Headers.GetEnumerator() | ForEach-Object -Process {Write-Debug -Message "`t                : $($_.Name)`t$($_.Value)"}
    Write-Debug -Message "`tBody            : $($sRest.Body)"
		
    # The intermediate $result is used to avoid returning a PSMemberSet
    Try
    {$result = Invoke-RestMethod @sRest}
    Catch
    {
      $excpt = $_.Exception

      Write-Debug -Message 'Exception'
      Write-Debug -Message "`tERROR-CODE = $($excpt.Response.Headers['ERROR-CODE'])"
      Write-Debug -Message "`tERROR-CODE = $($excpt.Response.Headers['ERROR-MESSAGE'])"
      Throw "$($excpt.Response.Headers['ERROR-CODE']) $($excpt.Response.Headers['ERROR-MESSAGE'])"
    }
    $result
    Write-Debug -Message 'Leaving Invoke-hRavelloRest'
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-hRavelloAuthHeader
{
  [CmdletBinding()]
  param ()
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
		
    $User = $Script:RavelloCredential.UserName
    $Password = $Script:RavelloCredential.GetNetworkCredential().password
		
    $Encoded = [System.Text.Encoding]::UTF8.GetBytes(($User, $Password -Join ':'))
    $EncodedPassword = [System.Convert]::ToBase64String($Encoded)
    Write-Debug -Message "`tEncoded  : $($EncodedPassword)"
		
    @{
      'Authorization' = "Basic $($EncodedPassword)"
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Update-hRavelloField
{
  Param(
    [PSObject]$Object,
    [string]$Property,
    $Value
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if([bool]($Object.PSobject.Properties.name -match $Property))
    {$Object.$($Property) = $Value}
    else
    {$Object | Add-Member -Name $Property -Value $Value -MemberType NoteProperty}
  }
}
#endregion

#region Import
# .ExternalHelp Ravello-Help.xml
function Import-Ravello
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [string]$CliPath = 'C:\Ravello_cli',
    [Parameter(Mandatory = $True, ParameterSetName = 'ISO')]
    [string]$IsoPath,
    [Parameter(Mandatory = $True, ParameterSetName = 'VM')]
    [string]$VmPath,
    [Parameter(Mandatory = $True, ParameterSetName = 'vSphere')]
    [string]$EsxVmPath,
    [Parameter(Mandatory = $True, ParameterSetName = 'vSphere')]
    [string]$EsxServer,
    [Parameter(Mandatory = $True, ParameterSetName = 'vSphere')]
    [System.Management.Automation.PSCredential]$EsxCredential,
    [Parameter(Mandatory = $True, ParameterSetName = 'vDisk')]
    [string]$DiskPath
  )
	
  Begin
  {
    $cmd = '#clipath#\ravello.exe #importtype# -u #user#'
  }
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
		
    if (!(Test-Path -Path "$CliPath\ravello.exe"))
    {Write-Error -Message "Could not find ravello.exe in $($CliPath)"}
    else
    {
      if (!$Script:RavelloCredential)
      {Write-Error -Message 'You need to connect to Ravello before uploading files'}
      else
      {
        $User = $Script:RavelloCredential.UserName
        $pswd = $Script:RavelloCredential.GetNetworkCredential().password
				
        $oldRPswd = Get-Item -Path "Env:$($rPswd)" -ErrorAction SilentlyContinue
        $env:RAVELLO_PASSWORD = $pswd
				
        $cmd = $cmd.Replace('#clipath#', $CliPath)
        $cmd = $cmd.Replace('#user#', $User)
				
        if ($PSCmdlet.ParameterSetName -eq 'ISO')
        {
          if (Test-Path -Path $IsoPath)
          {
            $cmd = $cmd.Replace('#importtype#', 'import-disk')
            $cmd = $cmd, $IsoPath -join ' '
          }
          else
          {Write-Error -Message "Can't find ISO file $($IsoPath)"}
        }
        else
        {
          $cmd = $cmd.Replace('#importtype#', 'import')
          if ($PSCmdlet.ParameterSetName -eq 'VM')
          {
            if (Test-Path -Path $VmPath)
            {$cmd = $cmd, $VmPath -join ' '}
            else
            {Write-Error -Message "Can't find VM file $($VmPath)"}
          }
          elseif ($PSCmdlet.ParameterSetName -eq 'vSphere')
          {
            $vUser = $EsxCredential.UserName
            $vPswd = $EsxCredential.GetNetworkCredential().password
						
            $cmd = $cmd, 
            '--vm_configuration_file_path', """$($EsxVmPath)""", 
            '--server_username', $vUser, 
            '--server_password', $vPswd, 
            '--server_address', $EsxServer -join ' '
          }
          elseif ($PSCmdlet.ParameterSetName -eq 'vDisk')
          {
            if (Test-Path -Path $DiskPath)
            {$cmd = $cmd, '--disk', $DiskPath -join ' '}
            else
            {Write-Error -Message "Can't find VMDK file $($DiskPath)"}
          }
        }
				
        If ($PSCmdlet.ShouldProcess("Importing with $($cmd)"))
        {
          $result = &([scriptblock]::Create($cmd))
          #          $result = Invoke-Expression -Command $cmd
          if (!($result -notmatch 'upload.finished.successfully'))
          {Write-Warning -Message 'Upload might have failed - check the log'}
        }
        if ($oldRPswd)
        {$env:RAVELLO_PASSWORD = $oldRPswd}
        else
        {Remove-Item -Path Env:\RAVELLO_PASSWORD}
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloImportHistory
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [string]$CliPath = 'C:\Ravello_cli'
  )
	
  Begin
  {
    $cmd = '#clipath#\ravello.exe list -y'
    $pattern = 'name:\s(?<Filename>.+)\s+id:\s(?<Id>\d+)\s+creation time:\s(?<Date>[^\n\r]+)\s+.+ (?<Perc>\d+)%'
  }
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
		
    if (!(Test-Path -Path "$CliPath\ravello.exe"))
    {Write-Error -Message "Could not find ravello.exe in $($CliPath)"}
    else
    {
      $cmd = $cmd.Replace('#clipath#', $CliPath)
      If ($PSCmdlet.ShouldProcess("Listing import jobs with $($cmd)"))
      {
        #        Invoke-Expression -Command $cmd |
        &([scriptblock]::Create($cmd)) |
        Out-String |
        Select-String -AllMatches -Pattern $pattern |
        Select-Object -ExpandProperty Matches |
        ForEach-Object{
          $obj = [ordered]@{
            Filename   = $_.Groups['Filename'].Value
            JobId      = $_.Groups['Id'].Value
            Date       = [DateTime]$_.Groups['Date'].Value
            Percentage = $_.Groups['Perc'].Value
          }
          New-Object -TypeName PSObject -Property $obj
        }
      }
    }
  }
}

#endregion

#region General
# .ExternalHelp Ravello-Help.xml
function Connect-Ravello
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True,
        ValueFromPipeline = $True,
    ParameterSetName = 'Credential')]
    [System.Management.Automation.PSCredential]$Credential,
    [Parameter(Mandatory = $True,
    ParameterSetName = 'PlainText')]
    [String]$User,
    [Parameter(Mandatory = $True,
    ParameterSetName = 'PlainText')]
    [String]$Password,
    [string]$Proxy,
    [Parameter(DontShow)]
    [switch]$Fiddler = $false
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($Proxy)
    {
      if ($PSDefaultParameterValues.ContainsKey('*:Proxy'))
      {$PSDefaultParameterValues['*:Proxy'] = $Proxy}
      else
      {$PSDefaultParameterValues.Add('*:Proxy', $Proxy)}
      if ($PSDefaultParameterValues.ContainsKey('*:ProxyUseDefaultCredentials'))
      {$PSDefaultParameterValues['*:ProxyUseDefaultCredentials'] = $True}
      else
      {$PSDefaultParameterValues.Add('*:ProxyUseDefaultCredentials', $True)}
    }
    if ($PSCmdlet.ParameterSetName -eq 'PlainText')
    {
      $sPswd = ConvertTo-SecureString -String $Password -AsPlainText -Force
      $Script:RavelloCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($User, $sPswd)
    }
    if ($PSCmdlet.ParameterSetName -eq 'Credential')
    {$Script:RavelloCredential = $Credential}
    $Script:AuthHeader = Get-hRavelloAuthHeader
    $sConnect = @{
      Method  = 'Post'
      Request = 'login'
    }
    if ($Fiddler)
    {
      if (Get-Process -Name fiddler -ErrorAction SilentlyContinue)
      {
        if ($PSDefaultParameterValues.ContainsKey('Invoke-RestMethod:Proxy'))
        {$PSDefaultParameterValues['Invoke-RestMethod:Proxy'] = 'http://127.0.0.1:8888'}
        else
        {$PSDefaultParameterValues.Add('Invoke-RestMethod:Proxy', 'http://127.0.0.1:8888')}
      }
    }
    If ($PSCmdlet.ShouldProcess('Connecting to Ravello'))
    {Invoke-hRavelloRest @sConnect}
  }
}

# .ExternalHelp Ravello-Help.xml
function Disconnect-Ravello
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param ()
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    If ($PSCmdlet.ShouldProcess('Disconnecting from Ravello'))
    {
      Invoke-hRavelloRest -Method Post -Request 'logout'
			
      # Issue with Invoke-RestMethod (see Connect #836732) 
      $servicePoint = [System.Net.ServicePointManager]::FindServicePoint($RavelloBaseUrl)
      [void]$servicePoint.CloseConnectionGroup('')
			
      Remove-Variable -Name 'RavelloCredential' -Scope Script -Confirm:$false
      Remove-Variable -Name 'RavelloSession' -Scope Script -Confirm:$false
    }
  }
}
#endregion

#region Applications
# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'All')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameDesign')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameDeployment')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameProperties')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppId')]
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppIdDesign')]
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppIdDeployment')]
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppIdProperties')]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameDesign')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdDesign')]
    [Switch]$Design,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameDeployment')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdDeployment')]
    [Switch]$Deployment,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameProperties')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdProperties')]
    [Switch]$Properties,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    $sApp = @{
      Method  = 'Get'
      Request = 'applications'
    }

    $noParam = $false
    $appFound = $false
    if($ApplicationName)
    {
      $app = Get-RavelloApplication -Raw | Where-Object{$_.name -eq $ApplicationName}
      if($app)
      {
        $sApp.Request = $sApp.Request, "$([string]$app.id)" -join '/'
        $appFound = $True
      }
    }
    elseif($ApplicationId -gt 0)
    {
      $app = Get-RavelloApplication -Raw | Where-Object{$_.id -eq $ApplicationId}
      if($app)
      {
        $sApp.Request = $sApp.Request, "$([string]$app.id)" -join '/'
        $appFound = $True
      }
    }
    else
    {$noParam = $True}
    if($noParam -or $appFound)
    {
      if($Design)
      {$sApp.Request = $sApp.Request, 'design' -join ';'}
      if($Deployment)
      {$sApp.Request = $sApp.Request, 'deployment' -join ';'}
      if($Properties)
      {$sApp.Request = $sApp.Request, 'properties' -join ';'}
      If ($PSCmdlet.ShouldProcess('Retrieving Application'))
      {
        $app = Invoke-hRavelloRest @sApp
        if (!$Raw)
        {Convert-hRavelloTimeField -Object $app}
        $app
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High', DefaultParameterSetName = 'AllParameterSets')]
  param (
    [Parameter(Mandatory = $True)]
    [string]$ApplicationName,
    [string]$Description,
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName')]
    [string]$BlueprintName,
    [Parameter(Mandatory = $True, ParameterSetName = 'VmId')]
    [long[]]$VmImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'VmName')]
    [string[]]$VmImageName,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    # Create minimal Application
    $sApp = @{
      Method  = 'Post'
      Request = 'applications'
      Body    = @{
        name        = $ApplicationName
        description = $Description
      }
    }
    if($BlueprintName)
    {
      $bp = Get-RavelloBlueprint -BlueprintName $BlueprintName -Raw
      $BlueprintId = $bp.id
    }
    if($BlueprintId -ne 0)
    {$sApp.Body.Add('baseBlueprintId',$BlueprintId)}
    if($VmImageName)
    {$vms = $VmImageName | ForEach-Object{Get-RavelloImage -ImageName $_ -Raw}}
    if($VmImageId)
    {$vms = $VmImageId | ForEach-Object{Get-RavelloImage -ImageId $_ -Raw}}
    if($vms)
    {
      $sApp.Body.Add('design',@{
          'vms' = @($vms)
      })
    }
    If ($PSCmdlet.ShouldProcess('Create application'))
    {
      $app = Invoke-hRavelloRest @sApp
      if (!$Raw)
      {Convert-hRavelloTimeField -Object $app}
      $app
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [string]$NewApplicationName,
    [string]$NewDescription
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName -Raw
      $ApplicationId = $app.id
    }
    else
    {$app = Get-RavelloApplication -ApplicationId $ApplicationId -Raw}
    $sApp = @{
      Method  = 'Put'
      Request = "applications/$($ApplicationId)"
      Body    = $app
    }
    if ($NewApplicationName)
    {$sApp.Body.name = $NewApplicationName}
		
    if ($NewDescription)
    {$sApp.Body.description = $NewDescription}
		
    If ($PSCmdlet.ShouldProcess('Changing application'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppId')]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    $sApp = @{
      Method  = 'Delete'
      Request = "applications/$($ApplicationId)"
    }
    If ($PSCmdlet.ShouldProcess('Removing application'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationPublishLocation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [string]$PreferredCloud
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/findPublishLocations"
      Body    = @{
        id = $ApplicationId
      }
    }
		
    if ($PreferredCloud)
    {$sApp.Body.Add('preferredCloud', $PreferredCloud)}
    If ($PSCmdlet.ShouldProcess('Find application publishing site'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Publish-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppId')]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [ValidateScript({
          ((Get-RavelloApplication -ApplicationName $ApplicationName), (Get-RavelloApplication -ApplicationId $ApplicationId) |
          Get-RavelloApplicationPublishLocation).cloudName -contains $_
    })]
    [string]$PreferredCloud,
    [ValidateScript({
          ((Get-RavelloApplication -ApplicationName $ApplicationName), (Get-RavelloApplication -ApplicationId $ApplicationId) |
            Get-RavelloApplicationPublishLocation |
          Where-Object{$_.cloudName -eq $PreferredCloud}).regionName -contains $_
    })]
    [string]$PreferredRegion,
    [ValidateSet('COST_OPTIMIZED', 'PERFORMANCE_OPTIMIZED')]
    [string]$OptimizationLevel,
    [Switch]$StartAllVM = $false
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/publish"
      Body    = @{
        id          = [string]$ApplicationId
        startAllVms = ([string]$StartAllVM).ToLower()
      }
    }
    if ($PreferredCloud)
    {$sApp.Body.Add('preferredCloud', $PreferredCloud)}
    if ($PreferredRegion)
    {$sApp.Body.Add('preferredRegion', $PreferredRegion)}
    if ($OptimizationLevel)
    {$sApp.Body.Add('optimizationLevel', $OptimizationLevel)}
    If ($PSCmdlet.ShouldProcess('Publish application'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationVmVnc
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [long]$VmId
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sApp = @{
      Method = 'Get'
    }
    if ($ApplicationName -and $ApplicationId -eq 0)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      if ($app)
      {$ApplicationId = $app.id}
    }
    elseif ($ApplicationId -ne 0)
    {$app = Get-RavelloApplication -ApplicationId $ApplicationId}
    if ($VmId -ne 0)
    {
      $vm = Get-RavelloApplicationVm -ApplicationId $app.id -VmId $VmId -Deployment
      if ($vm.State -eq 'STARTED')
      {
        $sApp.Request = "applications/$($ApplicationId)/vms/$($VmId)/vncUrl"
        If ($PSCmdlet.ShouldProcess('Get VNC Url'))
        {Invoke-hRavelloRest @sApp}
      }
    }
    elseif ($app.deployment.vms -and $VmName)
    {
      $app.deployment.vms |
      Where-Object{$_.State -eq 'STARTED' -and $_.Name -eq $VmName} |
      ForEach-Object{
        $sApp.Request = "applications/$($ApplicationId)/vms/$($_.id)/vncUrl"
        If ($PSCmdlet.ShouldProcess('Get VNC Url'))
        {Invoke-hRavelloRest @sApp}
      }
    }
    elseif ($app.deployment.vms)
    {
      $app.deployment.vms |
      Where-Object{$_.State -eq 'STARTED'} |
      ForEach-Object{
        $sApp.Request = "applications/$($ApplicationId)/vms/$($_.id)/vncUrl"
        If ($PSCmdlet.ShouldProcess('Get VNC Url'))
        {
          New-Object -TypeName PsObject -Property @{
            VmName = $_.Name
            VncUrl = (Invoke-hRavelloRest @sApp)
          }
        }
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationCharge
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-Design', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-Design')]
    [Alias('name')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-Design')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-Design')]
    [ValidateSet('COST_OPTIMIZED','PERFORMANCE_OPTIMIZED')]
    [string]$Optimization,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-Design')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-Design')]
    [ValidateSet('AMAZON','GOOGLE')]
    [string]$Cloud,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-Design')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-Design')]
    [ValidateSet('Virginia','Oregon','Northern California','Ireland','Singapore','Frankfurt',
    'Sydney','Tokyo','SaoPaulo (AMAZON)','us-central1','europe-west1','asia-east1 (GOOGLE)')]
    [string]$Region
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/calcPrice;deployment"
    }
    if('AppName-Design', 'AppId-Design' -contains $PSCmdlet.ParameterSetName)
    {
      $sApp.Add('Body',@{
          'optimizationLevel' = $Optimization
          'cloudName'       = $Cloud
          'regionDisplayName' = $Region
      })
      $sApp.Request = $sApp.Request.Replace('deployment','design')
    }
    If ($PSCmdlet.ShouldProcess('Get application charges'))
    {Invoke-hRavelloRest @sApp}
    
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationVmFqdn
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [long]$VmId
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sApp = @{
      Method = 'Get'
    }
    if($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName -Design -Raw
      $ApplicationId = $app.id
    }
    $app = Get-RavelloApplication -ApplicationId $ApplicationId -Raw
    $vm = $app.deployment.vms | Where-Object{$_.name -eq $VmName -or $_.id -eq $ApplicationId}
    if($vm)
    {
      $sApp = @{
        Method  = 'Get'
        Request = "applications/$($app.id)/vms/$($vm.id)/fqdn;deployment"
      }
      If ($PSCmdlet.ShouldProcess('Get VM FQDN'))
      {Invoke-hRavelloRest @sApp}
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationVmState
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [long]$VmId
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    if($VmName)
    {
      $vm = Get-RavelloApplicationVm -ApplicationId $ApplicationId -VmName $VmName
      $VmId = $vm.id
    }
    $sApp = @{
      Method  = 'Get'
      Request = "applications/$($ApplicationId)/vms/$($VmId)/state;deployment"
    }
    If ($PSCmdlet.ShouldProcess('Get VM state'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationVmPublicIp
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [long]$VmId
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sApp = @{
      Method = 'Get'
    }
    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    if($VmName)
    {
      $vm = Get-RavelloApplicationVm -ApplicationId $ApplicationId -VmName $VmName
      $VmId = $vm.id
    }
    $sApp = @{
      Method  = 'Get'
      Request = "applications/$($ApplicationId)/vms/$($VmId)/publicIps;deployment"
    }
    If ($PSCmdlet.ShouldProcess('Get Public IPs'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Test-RavelloApplicationPublished
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    $sApp = @{
      Method  = 'Get'
      Request = "applications/$($ApplicationId)/isPublished"
    }
    If ($PSCmdlet.ShouldProcess('Test if application is published'))
    {[Boolean](Invoke-hRavelloRest @sApp).Value}
        
  }
}

# .ExternalHelp Ravello-Help.xml
function Add-RavelloApplicationVm
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-ImageId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-ImageName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-ImageId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-ImageName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-ImageName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-ImageName')]
    [string]$ImageName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-ImageId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-ImageId')]
    [long]$ImageId,
    [string]$NewVmName,
    [string]$NewVmDescription,
    [Parameter(DontShow)]
    [switch]$Raw
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    if($ImageName)
    {
      $image = Get-RavelloImage -ImageName $ImageName
      $ImageId = $image.id
    }
    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/vms"
      Body    = @{
        'baseVmId' = $ImageId
      }
    }
    If ($PSCmdlet.ShouldProcess('Add VM image to application'))
    {
      $app = Invoke-hRavelloRest @sApp |
      Set-RavelloApplicationVm -VmName $ImageName -NewName $NewVmName -NewDescription $NewVmDescription
      if(!$Raw)
      {Convert-hRavelloTimeField -Object $app}
      $app
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationVm
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [long]$VmId,
    [Switch]$Deployment,
    [Switch]$Design,
    [Parameter(DontShow)]
    [switch]$Raw
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName -Design -Raw
      $ApplicationId = $app.id
    }
    if('AppId','AppName' -contains $PsCmdlet.ParameterSetName)
    {
      $sAppVm = @{
        Method  = 'Get'
        Request = "applications/$($ApplicationId)/vms"
      }        
    }
    else
    {
      if($VmName)
      {
        $app = Get-RavelloApplication -ApplicationId $ApplicationId -Design -Raw
        $VmId = $app.design.vms |
        Where-Object{$_.name -eq $VmName} |
        Select-Object -ExpandProperty id
      }
      $sAppVm = @{
        Method  = 'Get'
        Request = "applications/$($ApplicationId)/vms/$($VmId)"
      }
    }
    if($Design)
    {$sAppVm.Request = $sAppVm.Request, 'design' -join ';'}
    if($Deployment)
    {$sAppVm.Request = $sAppVm.Request, 'deployment' -join ';'}
    If ($PSCmdlet.ShouldProcess('Get Application VM'))
    {
      $vm = Invoke-hRavelloRest @sAppVm
      if(!$Raw)
      {Convert-hRavelloTimeField -Object $vm}
      $vm
    } 
  }   
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloApplicationVm
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [long]$VmId,
    [string]$NewName,
    [string]$NewDescription,
    [string[]]$HostNames,
    [long]$NumCpu,
    [ValidateSet('GB', 'MB', 'KB', 'BYTE')]
    [string]$MemorySizeUnit = 'GB',
    [long]$MemorySize
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
    
    $sApp = @{
      'Raw' = $True
    }
    $PSBoundParameters.GetEnumerator() |
    Where-Object{$_.Key -match '^Application'} |
    ForEach-Object{$sApp.Add($_.Key, $_.Value)}
    $app = Get-RavelloApplication @sApp
    $vms = @()
    $vms += $app.Design.Vms | ForEach-Object{
      if($_.id -eq $VmId -or $_.name -eq $VmName)
      {
        if($NewName)
        {$_.name = $NewName}
        if($NewDescription)
        {$_.Description = $NewDescription}
        if($HostNames)
        {
          if($_.psobject.properties.Name -contains 'hostnames')
          {
            $_.hostnames = $HostNames
          }
          else
          {
            Add-Member -InputObject $_ -Name 'hostnames' -Value $HostNames -MemberType NoteProperty
          }
        }
        if($NumCpu -ne 0)
        {$_.numCpus = $NumCpu}
        if($MemorySize -ne 0)
        {
          $_.memorySize.unit = $MemorySizeUnit
          $_.memorySize.value = $MemorySize
        }
      }
      $_
    }
    Update-hRavelloField -Object $app.design -Property 'vms' -Value $vms
    $sApp = @{
      Method  = 'Put'
      Request = "applications/$($app.id)"
      Body    = $app
    }
    If ($PSCmdlet.ShouldProcess('Changing application VM'))
    {
      $app = Invoke-hRavelloRest @sApp
      if(!$Raw)
      {Convert-hRavelloTimeField -Object $app}
      $app
    }
  }   
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloApplicationVmService
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [long]$VmId,
    [switch]$Rdp,
    [switch]$Ssh
  )
  
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
    
    $sApp = @{
      'Raw' = $True
    }
    $PSBoundParameters.GetEnumerator() |
    Where-Object{$_.Key -match '^Application'} |
    ForEach-Object{$sApp.Add($_.Key, $_.Value)}
    $app = Get-RavelloApplication @sApp
    $vms = @()
    $vms += $app.Design.Vms | ForEach-Object{
      if($_.id -eq $VmId -or $_.name -eq $VmName)
      {
        if($PSBoundParameters.ContainsKey('Rdp'))
        {
          if($Rdp)
          {
            $rdpObj = @(New-Object PSObject -Property @{
                external = $true
                portRange = 3389
                name = 'rdp'
                protocol = 'RDP'
            })
            if($_.psobject.properties.Name -contains 'suppliedServices')
            {
              if(!($_.suppliedServices | where{$_.name -eq 'rdp'}))
              {
                $_.suppliedServices += $rdpObj
              }
            }
            else
            {
              Add-Member -InputObject $_ -Name 'suppliedServices' -Value @($rdpObj) -MemberType NoteProperty
            }
          }
          else
          {
            if($_.psobject.properties.Name -contains 'suppliedServices')
            {
              $_.suppliedServices = @($_.suppliedServices | where{$_.name -ne 'rdp'})
            }    
          }
        }
        if($PSBoundParameters.ContainsKey('Ssh'))
        {
          if($Ssh)
          {
            $sshObj = @(New-Object PSObject -Property @{
                external = $true
                externalPort = 22
                name = 'ssh'
                protocol = 'SSH'
            })
            if($_.psobject.properties.Name -contains 'suppliedServices')
            {
              if(!($_.suppliedServices | where{$_.name -eq 'ssh'}))
              {
                $_.suppliedServices += $sshObj
              }
            }
            else
            {
              Add-Member -InputObject $_ -Name 'suppliedServices' -Value @($sshObj) -MemberType NoteProperty
            }
          }
          else
          {
            if($_.psobject.properties.Name -contains 'suppliedServices')
            {
              $_.suppliedServices = @($_.suppliedServices | where{$_.name -ne 'ssh'})
            }    
          }
        }
      }
      if($_.suppliedServices -eq $null)
      {
        $_.psobject.properties.Remove('suppliedServices')
      }
      $_
    }
    Update-hRavelloField -Object $app.design -Property 'vms' -Value $vms
    $sApp = @{
      Method  = 'Put'
      Request = "applications/$($app.id)"
      Body    = $app
    }
    If ($PSCmdlet.ShouldProcess('Configuring services on application VM'))
    {
      $app = Invoke-hRavelloRest @sApp
      if(!$Raw)
      {Convert-hRavelloTimeField -Object $app}
      $app
    }
      
  }    
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloApplicationVmDisk
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [long]$VmId,
    [ValidateSet('GB', 'MB', 'KB', 'BYTE')]
    [string]$DiskSizeUnit = 'GB',
    [long]$DiskSize
  )
  
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
    
    $sApp = @{
      'Raw' = $True
    }
    $PSBoundParameters.GetEnumerator() |
    Where-Object{$_.Key -match '^Application'} |
    ForEach-Object{$sApp.Add($_.Key, $_.Value)}
    $app = Get-RavelloApplication @sApp
    $vms = @()
    $vms += $app.Design.Vms | ForEach-Object{
      if($_.id -eq $VmId -or $_.name -eq $VmName)
      {
        $lastHdName = $_.hardDrives | where{$_.name -match "^hd"} | select -Last 1 -ExpandProperty name
        $_.hardDrives += New-Object PSObject -Property @{
          boot = $false
          controller = 'ide'
          name = $lastHdName.Replace($lastHdName[-1],[char](([int][char]$lastHdName[-1]) + 1))
          size = New-Object PSObject -Property @{
            unit = $DiskSizeUnit
            value = $DiskSize
          }
          type = 'DISK'
        }
      }
      $_
    }
    Update-hRavelloField -Object $app.design -Property 'vms' -Value $vms
    $sApp = @{
      Method  = 'Put'
      Request = "applications/$($app.id)"
      Body    = $app
    }
    If ($PSCmdlet.ShouldProcess('Configuring disks on application VM'))
    {
      $app = Invoke-hRavelloRest @sApp
      if(!$Raw)
      {Convert-hRavelloTimeField -Object $app}
      $app
    }
      
  }    
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloApplicationVm
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId')]
    [long]$VmId
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName -Design -Raw
      $ApplicationId = $app.id
    }
    if($VmName)
    {
      $vm = $app.design.vms | Where-Object{$_.name -eq $VmName}
      #      $vm = Get-RavelloApplication -ApplicationId $ApplicationId -VmName $VmName -Raw
      $VmId = $vm.id
    }
    $sApp = @{
      Method  = 'Delete'
      Request = "applications/$($ApplicationId)/vms/$($VmId)"
    }
    If ($PSCmdlet.ShouldProcess('Remove VM from application'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    $sApp = @{
      Method  = 'Get'
      Request = "applications/$($ApplicationId)/documentation"
    }
    If ($PSCmdlet.ShouldProcess('Get application documentation'))
    {Invoke-hRavelloRest @sApp | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloApplicationDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [string]$Documentation
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/documentation"
      Body    = @{
        'value' = $Documentation
      }
    }
    If ($PSCmdlet.ShouldProcess('Set application documentation'))
    {Invoke-hRavelloRest @sApp | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloApplicationDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [string]$Documentation
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    $sApp = @{
      Method  = 'Put'
      Request = "applications/$($ApplicationId)/documentation"
      Body    = @{
        'value' = $Documentation
      }
    }
    If ($PSCmdlet.ShouldProcess('Set application documentation'))
    {Invoke-hRavelloRest @sApp | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloApplicationDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    $sApp = @{
      Method  = 'Delete'
      Request = "applications/$($ApplicationId)/documentation"
    }
    If ($PSCmdlet.ShouldProcess('Remove application documentation'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Invoke-RavelloApplicationAction
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName = $True)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName', ValueFromPipelineByPropertyName = $True)]
    [string]$ApplicationName,
    [ValidateSet('PublishUpdates', 'Start', 'Stop', 'Restart', 'ResetDisks')]
    [String]$Action,
    [switch]$StartAllVms = $false
  )
	
  process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
		
    if($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName -Raw
      $ApplicationId = $app | Select-Object -ExpandProperty id
    }
    if($ApplicationId -and !$app)
    {$app = Get-RavelloApplication -ApplicationId $ApplicationId -Raw}
		
    $Action = $Action.ToLower().Replace('publishupdates', 'publishUpdates').Replace('resetdisks','resetDisks')
		
    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/$($Action)?startAllDraftVms=$(($StartAllVms.ToString()).ToLower())"
    }
    If ($PSCmdlet.ShouldProcess('Take action on VM'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Invoke-RavelloApplicationVMAction
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName = $True)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName = $True)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId', ValueFromPipelineByPropertyName = $True)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName', ValueFromPipelineByPropertyName = $True)]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName = $True)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName', ValueFromPipelineByPropertyName = $True)]
    [string[]]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName = $True)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId', ValueFromPipelineByPropertyName = $True)]
    [long[]]$VmId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId', ValueFromPipelineByPropertyName = $True)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName', ValueFromPipelineByPropertyName = $True)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId', ValueFromPipelineByPropertyName = $True)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName', ValueFromPipelineByPropertyName = $True)]
    [ValidateSet('stop', 'start', 'shutdown', 'poweroff', 'restart', 'redeploy', 'repair', 'resetDisk')]
    [string]$Action
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
		
    if($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName -Raw
      $ApplicationId = $app | Select-Object -ExpandProperty id
    }
    if($ApplicationId -and !$app)
    {$app = Get-RavelloApplication -ApplicationId $ApplicationId -Raw}

    if($VmName)
    {
      $VmId = $app.design.vms |
      Where-Object{$VmName -contains $_.Name} |
      Select-Object -ExpandProperty id
    }

    $sVM = @{
      Method = 'Post'
    }

    if($VmId.Count -gt 1)
    {
      $ids = @{
        'ids' = $VmId
      }
      $sVM.Add('Request',"applications/$($ApplicationId)/vms/$($Action)")
      $sVM.Add('Body',$ids)
    }
    else
    {$sVM.Add('Request',"applications/$($ApplicationId)/vms/$($VmId[0])/$($Action)")}
        
    If ($PSCmdlet.ShouldProcess('Perform action on VM'))
    {Invoke-hRavelloRest @sVM}
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloApplicationTimeout
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [long]$ExpirationFromNowSeconds = 7200,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName -Raw
      if ($app)
      {$ApplicationId = $app.id}
    }
    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/setExpiration"
      Body    = @{
        expirationFromNowSeconds = $ExpirationFromNowSeconds
      }
    }
    If ($PSCmdlet.ShouldProcess('Set Application VM timeout'))
    {
      $app = Invoke-hRavelloRest @sApp
      $app | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Test-RavelloApplicationPendingUpdate
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName', ValueFromPipelineByPropertyName)]
    [string]$ApplicationName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      if ($app)
      {$ApplicationId = $app.id}
    }
    $sApp = @{
      Method  = 'Get'
      Request = "applications/$($ApplicationId)/pendingUpdates"
    }
    If ($PSCmdlet.ShouldProcess('Test pending Application update'))
    {Invoke-hRavelloRest @sApp}
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationVmIso
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmName')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmId')]
    [Alias('id')]
    [long]$VmId,
    [string]$DeviceName = 'cdrom'
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sVmCD = @{ }
    $PSBoundParameters.GetEnumerator() |
    Where-Object{$_.Key -notmatch '^DeviceName'} |
    ForEach-Object{$sVmCD.Add($_.Key, $_.Value)}
    $vm = Get-RavelloApplicationVm @sVmCD
    $vm.hardDrives |
    Where-Object{$_.type -eq 'CDROM' -and $_.name -match $DeviceName} |
    ForEach-Object{
      If ($PSCmdlet.ShouldProcess('Get connected ISO'))
      {Get-RavelloDiskImage -DiskImageId $_.baseDiskImageId}
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloApplicationVmIso
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmNameIsoId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmNameIsoName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmIdIsoId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmIdIsoName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppIdVmNameIsoId')]
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppIdVmNameIsoName')]
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppIdVmIdIsoId')]
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppIdVmIdIsoName')]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppNameVmIdIsoId')]
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppNameVmIdIsoName')]
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppIdVmIdIsoId')]
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppIdVmIdIsoName')]
    [long]$VmId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmNameIsoId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmNameIsoName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmNameIsoId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmNameIsoName')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmNameIsoId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmIdIsoId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmNameIsoId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmIdIsoId')]
    [long]$DiskImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmNameIsoName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameVmIdIsoName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmNameIsoName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdVmIdIsoName')]
    [string]$DiskImageName,
    [string]$DeviceName = 'cdrom',
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $app = $null
    if($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName -Raw
      $ApplicationId = $app | Select-Object -ExpandProperty id
    }
    if($ApplicationId -and !$app)
    {$app = Get-RavelloApplication -ApplicationId $ApplicationId -Raw}
    if($VmName)
    {
      $VmId = $app.design.vms |
      Where-Object{$_.Name -eq $VmName} |
      Select-Object -ExpandProperty id
    }
    if($DiskImageName)
    {
      $img = Get-RavelloDiskImage -DiskImageName $DiskImageName -Raw
      $DiskImageId = $img | Select-Object -ExpandProperty id
    }
    if($DiskImageId -and !$img)
    {$img = Get-RavelloDiskImage -DiskImageId $DiskImageId -Raw}
    $updVm = @()
    foreach($vm in $app.design.vms)
    {
      if($vm.Name -eq $VmName -or $vm.id -eq $VmId)
      {
        $newDev = @()
        foreach($dev in $vm.hardDrives)
        {
          if($dev.type -eq 'CDROM' -and $dev.name -match $DeviceName)
          {
            $dev.size.value = $img.size.value
            $dev.size.unit = $img.size.unit
            if($dev.PSObject.Properties['baseDiskImageId'])
            {$dev.baseDiskImageId = $img.id}
            else
            {Add-Member -InputObject $dev -Name 'baseDiskImageId' -Value $img.id -MemberType NoteProperty}
            if($dev.PSObject.Properties['baseDiskImageName'])
            {$dev.baseDiskImageName = $img.name}
            else
            {Add-Member -InputObject $dev -Name 'baseDiskImageName' -Value $img.name -MemberType NoteProperty}
          }
          $newDev += $dev
        }
        $vm.hardDrives = $newDev
      }
      $updVm += $vm
    }

    $app.design.vms = $updVm
    $sApp = @{
      Method  = 'Put'
      Request = "applications/$($app.id)"
      Body    = $app
    }
    #        $sApp.Body.creationtime = 
    If ($PSCmdlet.ShouldProcess('Connect ISO to VM'))
    {
      $app = Invoke-hRavelloRest @sApp
      if(!$Raw)
      {Convert-hRavelloTimeField -Object $app}
      $app
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloApplicationOrderGroup
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName, ParameterSetName = 'AppId')]
    [Alias('id')]
    [long]$ApplicationId,
    [PSObject[]]$StartOrder,
    [switch]$Raw
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $app = $null
    if($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName -Design -Raw
      $ApplicationId = $app | Select-Object -ExpandProperty id
    }
    if($ApplicationId -and !$app)
    {$app = Get-RavelloApplication -ApplicationId $ApplicationId -Design -Raw}
    if($StartOrder)
    {
      $groups = @()
      $i = 1
      $StartOrder | ForEach-Object{
        $group = New-Object -TypeName PSObject -Property @{
          id    = $i
          name  = $_.Name
          order = $i
          delay = $_.DelaySeconds
        }
        if($_.VM)
        {
          foreach($vm in $app.design.vms)
          {
            if($_.VM -contains $vm.name)
            {Update-hRavelloField -Object $vm -Property 'vmOrderGroupId' -Value $group.id}
          }
        }
        $groups += $group
        $i++
      }
      Update-hRavelloField -Object $app.design -Property 'vmOrderGroups' -Value $groups 
    }
    $sApp = @{
      Method  = 'Put'
      Request = "applications/$($app.id)"
      Body    = $app
    }
    If ($PSCmdlet.ShouldProcess('Create startorder groups'))
    {
      $app = Invoke-hRavelloRest @sApp
      Invoke-RavelloApplicationAction -ApplicationId $app.id -Action PublishUpdates -Confirm:$false
      if(!$Raw)
      {Convert-hRavelloTimeField -Object $app}
      $app
    }
  }
}

#endregion Applications

#region Tasks
# .ExternalHelp Ravello-Help.xml
function Get-RavelloTask
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName = $True)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [long]$TaskId,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {$ApplicationId = Get-RavelloApplication -ApplicationName $ApplicationName | Select-Object -ExpandProperty id}
    $sTask = @{
      Method  = 'Get'
      Request = "applications/$($ApplicationId)/tasks"
    }
    if ($TaskId)
    {$sTask.Request = $sTask.Request.Replace('tasks', "tasks/$($TaskId)")}
    If ($PSCmdlet.ShouldProcess('Retrieve tasks'))
    {
      $tasks = Invoke-hRavelloRest @sTask
      $tasks | ForEach-Object{
        if(!$Raw)
        {
          Convert-hRavelloTimeField -Object $_
          $_
        }
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloTask
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdStart', ValueFromPipelineByPropertyName = $True)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdStop', ValueFromPipelineByPropertyName = $True)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdBP', ValueFromPipelineByPropertyName = $True)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameStart')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameStop')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameBP')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdStart')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameStart')]
    [switch]$StartTask,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdStop')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameStop')]
    [switch]$StopTask,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdBP')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameBP')]
    [switch]$BlueprintTask,
    [string]$Description,
    [DateTime]$Start,
    [DateTime]$Finish,
    [string]$Cron,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdBP')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameBP')]
    [switch]$Offline,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIdBP')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppNameBP')]
    [string]$BlueprintPrefix,
    [Parameter(ParameterSetName = 'AppIdBP')]
    [Parameter(ParameterSetName = 'AppNameBP')]
    [string]$BlueprintDescription
  )

  	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {$ApplicationId = Get-RavelloApplication -ApplicationName $ApplicationName | Select-Object -ExpandProperty id}
    $sTask = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/tasks"
      Body    = @{
        scheduleInfo = @{
          start          = ''
          end            = ''
          cronExpression = ''
        }
        description  = ''
      }
    }
    
    if('AppIdBP', 'AppNameBP' -contains $PSCmdlet.ParameterSetName)
    {
      $sTask.Body.Add('action','BLUEPRINT')
      $args = @{
        'namePrefix' = $BlueprintPrefix
        'isOffline' = $Offline.ToString().ToLower()
      }
      if($BlueprintDescription)
      {$args.Add('description',$BlueprintDescription)}
      $sTask.Body.Add('args',$args)
    }
    else
    {
      if($StartTask)
      {$sTask.Body.Add('action','START')}
      elseif($StopTask)
      {$sTask.Body.Add('action','STOP')}
    }

    # seconds in cron expression need to be 0 (zero)
    if ($Start)
    {$Start = $Start.ToUniversalTime().AddSeconds(- $Start.Second)}
    if ($Finish)
    {$Finish = $Finish.ToUniversalTime()}
    $t = (Get-Date).AddMinutes(10).ToUniversalTime()
		
    # seconds in cron expression need to be 0 (zero)
    if (!$Cron)
    {$Cron = "0 $($t.Minute) $($t.Hour) $($t.Day) $($t.Month) ? $($t.Year)"}
    $sTask.Body.scheduleInfo.cronExpression = $Cron
    if ($Start -and $Start -ge $t)
    {$sTask.Body.scheduleInfo.start = ConvertTo-hRavelloJsonDateTime -Date $Start}
    elseif ($Start -and $Start -lt $t)
    {$sTask.Body.scheduleInfo.start = ConvertTo-hRavelloJsonDateTime -Date $t}
    if ($Finish -and $Finish -ge $t)
    {$sTask.Body.scheduleInfo.end = ConvertTo-hRavelloJsonDateTime -Date $Finish}
    elseif ($Finish -and $Finish -lt $t)
    {$sTask.Body.scheduleInfo.end = ConvertTo-hRavelloJsonDateTime -Date $t}
    if ($Description -ne '')
    {$sTask.Body.description = $Description}
    If ($PSCmdlet.ShouldProcess('Start task'))
    {Invoke-hRavelloRest @sTask}
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloTask
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'TaskId', ValueFromPipelineByPropertyName = $True)]
    [Alias('id')]
    [long]$TaskId,
    [string]$NewDescription,
    [DateTime]$NewStart,
    [DateTime]$NewFinish,
    [string]$NewCron
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
		
    $task = Get-RavelloTask -TaskId $TaskId
    $sTask = @{
      Method  = 'Put'
      Request = "applications/$($task.entityId)/tasks/$($task.id)"
      Body    = @{
        args         = $task.args
        action       = $task.action
        entityId     = $task.entityId
        entityType   = $task.entityType
        id           = $task.id
        scheduleInfo = $task.scheduleInfo
        description  = $task.description
      }
    }
    if ($NewStart)
    {$NewStart = $NewStart.ToUniversalTime().AddSeconds(- $NewStart.Second)}
    if ($NewFinish)
    {$NewFinish = $NewFinish.ToUniversalTime().AddSeconds(- $NewFinish.Second)}
    if ($NewStart)
    {$sTask.Body.scheduleInfo.start = ConvertTo-hRavelloJsonDateTime -Date $NewStart}
    if ($NewFinish)
    {$sTask.Body.scheduleInfo.end = ConvertTo-hRavelloJsonDateTime -Date $NewFinish}
    if ($NewDescription)
    {$sTask.Body.description = $NewDescription}
    if($NewCron)
    {$sTask.Body.scheduleInfo.cronExpression}
    If ($PSCmdlet.ShouldProcess('Change task'))
    {Invoke-hRavelloRest @sTask}
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloTask
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId')]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [long]$TaskId
  )
	
  process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {$ApplicationId = Get-RavelloApplication -ApplicationName $ApplicationName | Select-Object -ExpandProperty id}
    $sTask = @{
      Method  = 'Delete'
      Request = "applications/$($ApplicationId)/tasks"
    }
    if ($TaskId)
    {$sTask.Request = $sTask.Request.Replace('tasks', "tasks/$($TaskId)")}
    If ($PSCmdlet.ShouldProcess('Remove task'))
    {Invoke-hRavelloRest @sTask}
  }
}
#endregion

#region Blueprints
# .ExternalHelp Ravello-Help.xml
function Get-RavelloBlueprint
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'BlueprintId')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BlueprintName')]
    [string]$BlueprintName,
    [Switch]$Private,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sBlue = @{
      Method  = 'Get'
      Request = 'blueprints'
    }
    if ($BlueprintName)
    {
      $BlueprintId = Get-RavelloBlueprint |
      Where-Object{$_.name -eq $BlueprintName} |
      Select-Object -ExpandProperty id
    }
    if ($BlueprintId)
    {$sBlue.Request = $sBlue.Request.Replace('blueprints', "blueprints/$($BlueprintId)")}
    if ($Private)
    {
      $org = Get-RavelloOrganization
      $sBlue.Request = $sBlue.Request.Replace('blueprints', "organizations/$($org.id)/blueprints")
    }
		
    If ($PSCmdlet.ShouldProcess('Retrieve blueprints'))
    {
      $bp = Invoke-hRavelloRest @sBlue
      $bp | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloBlueprint
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ApplicationId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'ApplicationName')]
    [string]$BlueprintName,
    [Parameter(Mandatory = $True, ParameterSetName = 'ApplicationId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ApplicationName')]
    [string]$ApplicationName,
    [string]$Description = '',
    [switch]$Offline,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ApplicationName)
    {
      $ApplicationId = Get-RavelloApplication |
      Where-Object{$_.Name -eq $ApplicationName} |
      Select-Object -ExpandProperty id
    }
    if ($ApplicationId)
    {
      $sBlue = @{
        Method  = 'Post'
        Request = 'blueprints'
        Body    = @{
          applicationId = $ApplicationId
          blueprintName = $BlueprintName
          offline       = ([string]$Offline).ToLower()
          description   = $Description
        }
      }
      If ($PSCmdlet.ShouldProcess('Create blueprint'))
      {
        $bp = Invoke-hRavelloRest @sBlue
        $bp | ForEach-Object{
          if(!$Raw)
          {Convert-hRavelloTimeField -Object $_}
          $_
        }
      }
    }
    else
    {Throw 'New-RavelloBlueprint requires an Application (Name or Id)'}
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloBlueprintPublishLocation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'BlueprintId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BlueprintName')]
    [string]$BlueprintName
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"
		
    if ($BlueprintName)
    {
      $BlueprintId = Get-RavelloBlueprint |
      Where-Object{$_.name -eq $BlueprintName} |
      Select-Object -ExpandProperty id
    }
    $sBlue = @{
      Method  = 'Post'
      Request = "blueprints/$($BlueprintId)/findPublishLocations"
      Body    = @{
        id = $BlueprintId
      }
    }
		
    if ($PreferredCloud)
    {$sBlue.Body.Add('preferredCloud', $PreferredCloud)}
    if ($PreferredRegion)
    {$sBlue.Body.Add('preferredRegionCloud', $PreferredRegion)}
    If ($PSCmdlet.ShouldProcess('Get blueprint publication location'))
    {Invoke-hRavelloRest @sBlue}
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloBlueprint
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'BlueprintId')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BlueprintName')]
    [string]$BlueprintName
  )
	
  process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($BlueprintName)
    {
      $BlueprintId = Get-RavelloBlueprint |
      Where-Object{$_.name -eq $BlueprintName} |
      Select-Object -ExpandProperty id
    }
    if ($BlueprintId)
    {
      $sBlue = @{
        Method  = 'Delete'
        Request = "blueprints/$($BlueprintId)"
      }
      If ($PSCmdlet.ShouldProcess('Remove blueprint'))
      {Invoke-hRavelloRest @sBlue}
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloBlueprintDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'BPId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BPName')]
    [string]$BlueprintName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($BlueprintName)
    {
      $bp = Get-RavelloBlueprint -BlueprintName $BlueprintName
      $BlueprintId = $bp.id
    }
    $sBP = @{
      Method  = 'Get'
      Request = "blueprints/$($ApplicationId)/documentation"
    }
    If ($PSCmdlet.ShouldProcess('Get blueprint documentation'))
    {Invoke-hRavelloRest @sBP | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloBlueprintDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'BPId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BPName')]
    [string]$BlueprintName,
    [string]$Documentation
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($BlueprintName)
    {
      $bp = Get-RavelloBlueprint -BlueprintName $BlueprintName
      $BlueprintId = $bp.id
    }
    $sBP = @{
      Method  = 'Post'
      Request = "blueprints/$($BlueprintId)/documentation"
      Body    = @{
        'value' = $Documentation
      }
    }
    If ($PSCmdlet.ShouldProcess('Set blueprint documentation'))
    {Invoke-hRavelloRest @sBP | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloBlueprintDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'BPId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BPName')]
    [string]$BlueprintName,
    [string]$Documentation
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($BlueprintName)
    {
      $bp = Get-RavelloBlueprint -BlueprintName $BlueprintName
      $BlueprintId = $bp.id
    }
    $sBP = @{
      Method  = 'Put'
      Request = "blueprints/$($BlueprintId)/documentation"
      Body    = @{
        'value' = $Documentation
      }
    }
    If ($PSCmdlet.ShouldProcess('Set blueprint documentation'))
    {Invoke-hRavelloRest @sBP | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloBlueprintDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'BPId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BPName')]
    [string]$BlueprintName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($BlueprintName)
    {
      $bp = Get-RavelloBlueprint -BlueprintName $BlueprintName
      $BlueprintId = $bp.id
    }
    $sBP = @{
      Method  = 'Delete'
      Request = "blueprints/$($BlueprintId)/documentation"
    }
    If ($PSCmdlet.ShouldProcess('Remove application documentation'))
    {Invoke-hRavelloRest @sBP}
  }
}
#endregion

#region Images
# .ExternalHelp Ravello-Help.xml
function Get-RavelloImage
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageName')]
    [string]$ImageName,
    [Parameter(Mandatory = $True, ParameterSetName = 'Private')]
    [switch]$Private,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sImage = @{
      Method  = 'Get'
      Request = 'images'
    }
		
    Switch($PSCmdlet.ParameterSetName)
    {
      {'ImageName', 'ImageId' -contains $_}
      {
        if($ImageName)
        {
          $img = Get-RavelloImage -Raw | Where-Object{$_.Name -eq $ImageName}
          $ImageId = $img.id
        }
        $sImage.Request = $sImage.Request.Replace('images', "images/$($ImageId)")
      }
      'Private'
      {
        $org = Get-RavelloOrganization
        $sImage.Request = $sImage.Request.Replace('images', "organizations/$($org.id)/images")
      }
    }
    If ($PSCmdlet.ShouldProcess('Get image'))
    {
      $image = Invoke-hRavelloRest @sImage
      $image | ForEach-Object{
        if (!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloImage
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    #    [string]$Name,
    [Parameter(Mandatory = $True, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$AppBpId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ApplicationName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'BlueprintName')]
    [string]$BlueprintName,
    [long]$VmId,
    [string]$VmName,
    [string]$NewImageName,
    [switch]$Offline = $false,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($AppBpId)
    {
      if (Get-RavelloApplication -ApplicationId $AppBpId -Properties -Raw -ErrorAction SilentlyContinue)
      {
        $blueprint = $false
        $ApplicationId = $AppBpId
      }
      else
      {
        $blueprint = $True
        $BlueprintId = $AppBpId
      }
    }
		
    if ($BlueprintId -or $BlueprintName)
    {
      $blueprint = $True
      if ($BlueprintName)
      {
        $bp = Get-RavelloBlueprint -BlueprintName $BlueprintName -Raw
        $AppBpId = $bp.id
      }
      else
      {$bp = Get-RavelloBlueprint -BlueprintId $AppBpId -Raw} 
      if ($VmName)
      {
        $VmId = $bp.design.vms |
        Where-Object{$_.Name -eq $VmName} |
        Select-Object -ExpandProperty id
      }
    }
    else
    {
      $blueprint = $false
      if ($ApplicationName)
      {$AppBpId = Get-RavelloApplication -ApplicationName $ApplicationName -Design -Raw | Select-Object -ExpandProperty id}
      if ($VmName)
      {$VmId = Get-RavelloApplicationVm -ApplicationId $AppBpId -VmName $VmName | Select-Object -ExpandProperty id}
    }
    $sImage = @{
      Method  = 'Post'
      Request = 'images'
      Body    = @{
        applicationId = $AppBpId
        vmId          = $VmId
        offline       = ($Offline.ToString()).ToLower()
        blueprint     = $blueprint
        imageName     = $NewImageName
      }
    }
    If ($PSCmdlet.ShouldProcess('Create image'))
    {
      $image = Invoke-hRavelloRest @sImage
      $image | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloImage
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageName')]
    [string]$ImageName,
    [string]$NewDescription,
    [string]$NewName,
    [long]$NumCpu,
    [ValidateSet('GB', 'MB', 'KB', 'BYTE')]
    [string]$MemorySizeUnit,
    [long]$MemorySize
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ImageName)
    {$img = Get-RavelloImage -ImageName $ImageName -Raw}
    else
    {$img = Get-RavelloImage -ImageId $ImageId -Raw}
    $sImage = @{
      Method  = 'Put'
      Request = "images/$($img.id)"
      Body    = $img
    }
    if($NewName)
    {$sImage.Body.name = $NewName}		
    if ($NewDescription)
    {$sImage.Body.description = $NewDescription}
    if ($NumCpu)
    {$sImage.Body.numCpus = $NumCpu}
    if ($MemorySizeUnit)
    {$sImage.Body.memorySize.unit = $MemorySizeUnit}
    if ($MemorySize)
    {$sImage.Body.memorySize.value = $MemorySize}

    If ($PSCmdlet.ShouldProcess('Change image'))
    {
      Invoke-hRavelloRest @sImage | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloImage
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageName')]
    [string]$ImageName
  )
	
  process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ImageName)
    {$ImageId = Get-RavelloImage -ImageName $ImageName | Select-Object -ExpandProperty id}
		
    $sImage = @{
      Method  = 'Delete'
      Request = "images/$($ImageId)"
    }
    If ($PSCmdlet.ShouldProcess('Remove image'))
    {Invoke-hRavelloRest @sImage}
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloImageDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageName')]
    [string]$ImageName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ImageName)
    {
      $img = Get-RavelloImage -ImageName $ImageName
      $ImageId = $img.id
    }
    $sIm = @{
      Method  = 'Get'
      Request = "images/$($ImagesId)/documentation"
    }
    If ($PSCmdlet.ShouldProcess('Get image documentation'))
    {Invoke-hRavelloRest @sIm | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloImageDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageName')]
    [string]$ImageName,
    [string]$Documentation
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ImageName)
    {
      $img = Get-RavelloImage -ImageName $ImageName
      $ImageId = $img.id
    }
    $sIm = @{
      Method  = 'Post'
      Request = "images/$($ImageId)/documentation"
      Body    = @{
        'value' = $Documentation
      }
    }
    If ($PSCmdlet.ShouldProcess('Set image documentation'))
    {Invoke-hRavelloRest @sIm | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloImageDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageName')]
    [string]$ImageName,
    [string]$Documentation
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ImageName)
    {
      $img = Get-RavelloImage -ImageName $ImageName
      $ImageId = $img.id
    }
    $sIm = @{
      Method  = 'Put'
      Request = "images/$($ImageId)/documentation"
      Body    = @{
        'value' = $Documentation
      }
    }
    If ($PSCmdlet.ShouldProcess('Set image documentation'))
    {Invoke-hRavelloRest @sIm | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloImageDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ImageName')]
    [string]$ImageName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($ImageName)
    {
      $img = Get-RavelloImage -ImageName $ImageName
      $ImageId = $img.id
    }
    $sIm = @{
      Method  = 'Delete'
      Request = "images/$($ImageId)/documentation"
    }
    If ($PSCmdlet.ShouldProcess('Remove image documentation'))
    {Invoke-hRavelloRest @sIm}
  }
}
#endregion

#region Diskimages
# .ExternalHelp Ravello-Help.xml
function Get-RavelloDiskImage
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(ParameterSetName = 'DiskImageId')]
    [long]$DiskImageId,
    [Parameter(ParameterSetName = 'DiskImageName')]
    [string]$DiskImageName,
    [switch]$SharedWithMe,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $p2pValue = 0
    if($SharedWithMe)
    {$p2pValue = 1}
    if ($DiskImageName)
    {
      $image = Get-RavelloDiskImage | Where-Object{$_.name -eq $DiskImageName}
      if($image)
      {$DiskImageId = $image.id}
      else
      {$DiskImageId = -1}
    }
    $sDiskImage = @{
      Method  = 'Get'
      Request = 'diskImages'
    }
    if ($DiskImageId -gt 0)
    {$sDiskImage.Request = $sDiskImage.Request.Replace('diskImages', "diskImages/$($DiskImageId)")}
    If ($PSCmdlet.ShouldProcess('Get disk images'))
    {
      if($DiskImageId -ne -1)
      {
        $disk = Invoke-hRavelloRest @sDiskImage
        $disk | 
        Where-Object{$_.peerToPeerShares -eq $p2pValue} |
        ForEach-Object{
          if(!$Raw)
          {Convert-hRavelloTimeField -Object $_}
          $_
        }
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloDiskImage
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId-DiskId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId-DiskName', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName-DiskId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName-DiskName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName-DiskName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmId-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmName-DiskName')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmId-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmName-DiskName')]
    [string]$BlueprintName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmId-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmId-DiskId')]
    [long]$VmId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmName-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmName-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmName-DiskId')]
    [string]$VmName,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmId-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmName-DiskId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmId-DiskId')]
    [long]$DiskId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmName-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmName-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmName-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName-VmId-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmName-DiskName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId-VmId-DiskName')]
    [string]$DiskName,
    [Parameter(Mandatory = $True)]
    [string]$NewDiskName,
    [string]$Description,
    [switch]$Offline = $false,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if($ApplicationId -gt 0)
    {
      $blueprint = $false
      $obj = Get-RavelloApplication -ApplicationId $ApplicationId -Raw
    }
    elseif($BlueprintId -gt 0)
    {
      $obj = Get-RavelloBlueprint -BlueprintId $BlueprintId -Raw
      $blueprint = $True
    }
    elseif ($ApplicationName)
    {
      $obj = Get-RavelloApplication -ApplicationName $ApplicationName -Raw
      $blueprint = $false
    }
    elseif ($BlueprintName)
    {
      $obj = Get-RavelloBlueprint -BlueprintName $BlueprintName -Raw
      $blueprint = $True
    }

    $Id = $obj.id
    if ($VmName)
    {
      $objVm = $obj.design.vms | Where-Object{$_.name -eq $VmName}
      $VmId = $objVm.id
    }
    else
    {
      $objVm = $obj.design.vms | Where-Object{$_.id -eq $VmId}
    }
    if ($DiskName)
    {
      $objDisk = $objVm.hardDrives | Where-Object{$_.name -eq $DiskName}
      $DiskId = $objDisk.id
    }
		
    $sDiskImage = @{
      Method  = 'Post'
      Request = 'diskImages'
      Body    = @{
        applicationId = $Id
        vmId          = $VmId
        diskId        = $DiskId
        diskImage     = @{
          name = $NewDiskName
        }
        offline       = ($Offline.ToString()).ToLower()
        blueprint     = ($blueprint.ToString()).ToLower()
      }
    }
    If ($PSCmdlet.ShouldProcess('Create disk image'))
    {
      $disk = Invoke-hRavelloRest @sDiskImage
      $disk | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloDiskImage
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'DiskImageId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'DiskImageName')]
    [string]$DiskImageName,
    [string]$NewName,
    [string]$NewDescription,
    [ValidateSet('GB', 'MB', 'KB', 'BYTE')]
    [string]$NewSizeUnit,
    [long]$NewSize,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($DiskImageName)
    {$disk = Get-RavelloDiskImage -DiskImageName $DiskImageName -Raw}
    else
    {$disk = Get-RavelloDiskImage -DiskImageId $DiskImageId -Raw}
    if (!$NewName)
    {$NewName = $disk.name}
    if (!$NewSizeUnit)
    {$NewSizeUnit = $disk.size.unit}
    if (!$NewSize)
    {$NewSize = $disk.size.value}
    $sDiskImage = @{
      Method  = 'Put'
      Request = "diskImages/$($disk.id)"
      Body    = @{
        id   = $disk.id
        name = $NewName
        size = @{
          unit  = $NewSizeUnit
          value = $NewSize
        }
      }
    }
    if ($NewDescription)
    {$sDiskImage.Body.Add('description', $NewDescription)}
    If ($PSCmdlet.ShouldProcess('Change disk image'))
    {
      $newdisk = Invoke-hRavelloRest @sDiskImage
      $newdisk | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloDiskImage
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'DiskImageId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'DiskImageName')]
    [string]$DiskImageName
  )
	
  process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($DiskImageName)
    {$DiskImageId = Get-RavelloDiskImage -DiskImageName $DiskImageName | Select-Object -ExpandProperty id}
    $sDiskImage = @{
      Method  = 'Delete'
      Request = "diskImages/$($DiskImageId)"
    }
    If ($PSCmdlet.ShouldProcess('Remove disk image'))
    {Invoke-hRavelloRest @sDiskImage}
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloDiskImageDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'DIId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'DIName')]
    [string]$DiskImageName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($DiskImageName)
    {
      $dim = Get-RavelloDiskImage -DiskImageName $DiskImageName
      $DiskImageId = $dim.id
    }
    $sDim = @{
      Method  = 'Get'
      Request = "diskImages/$($ApplicationId)/documentation"
    }
    If ($PSCmdlet.ShouldProcess('Get diskimage documentation'))
    {Invoke-hRavelloRest @sDim | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloDiskImageDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'DIId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'DIName')]
    [string]$DiskImageName,
    [string]$Documentation
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($DiskImageName)
    {
      $dim = Get-RavelloDiskImage -DiskImageName $DiskImageName
      $DiskImageId = $dim.id
    }
    $sDim = @{
      Method  = 'Post'
      Request = "diskImages/$($DiskImageId)/documentation"
      Body    = @{
        'value' = $Documentation
      }
    }
    If ($PSCmdlet.ShouldProcess('Set diskimage documentation'))
    {Invoke-hRavelloRest @sDim | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloDiskImageDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'DIId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'DIName')]
    [string]$DiskImageName,
    [string]$Documentation
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($DiskImageName)
    {
      $dim = Get-RavelloDiskImage -DiskImageName $DiskImageName
      $DiskImageId = $dim.id
    }
    $sDim = @{
      Method  = 'Put'
      Request = "diskImages/$($DiskImageId)/documentation"
      Body    = @{
        'value' = $Documentation
      }
    }
    If ($PSCmdlet.ShouldProcess('Set diskimage documentation'))
    {Invoke-hRavelloRest @sDim | Select-Object -ExpandProperty value}
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloDiskImageDocumentation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'DIId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskImageId,
    [Parameter(Mandatory = $True, ParameterSetName = 'DIName')]
    [string]$DiskImageName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($DiskImageName)
    {
      $dim = Get-RavelloDiskImage -DiskImageName $DiskImageName
      $DiskImageId = $dim.id
    }
    $sDim = @{
      Method  = 'Delete'
      Request = "diskImages/$($DiskImageId)/documentation"
    }
    If ($PSCmdlet.ShouldProcess('Remove diskimage documentation'))
    {Invoke-hRavelloRest @sDim}
  }
}
#endregion

#region Key Pairs
# .ExternalHelp Ravello-Help.xml
function Get-RavelloKeyPair
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'KeyPairId')]
    [long]$KeyPairId,
    [Parameter(Mandatory = $True, ParameterSetName = 'KeyPairName')]
    [string]$KeyPairName,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sKeyPair = @{
      Method  = 'Get'
      Request = 'keypairs'
    }
    if ($KeyPairName)
    {
      $KeyPairId = Get-RavelloKeyPair |
      Where-Object{$_.Name -eq $KeyPairName} |
      Select-Object -ExpandProperty id
    }
    if ($KeyPairId)
    {$sKeyPair.Request = $sKeyPair.Request.Replace('keypairs', "keypairs/$($KeyPairId)")}
    If ($PSCmdlet.ShouldProcess('Get key pairs'))
    {
      $keypairs = Invoke-hRavelloRest @sKeyPair
      $keypairs | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloKeyPair
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'New')]
    [string]$KeyPairName,
    [Parameter(Mandatory = $True, ParameterSetName = 'New', ValueFromPipelineByPropertyName)]
    [string]$PublicKey,
    [Parameter(Mandatory = $True, ParameterSetName = 'Generate')]
    [switch]$Generate,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sKeyPair = @{
      Method  = 'Post'
      Request = 'keypairs'
    }
		
    if ($Generate)
    {$sKeyPair.Request = 'keypairs/generate'}
    else
    {
      $sKeyPair.Add('Body', @{
          'name'    = $KeyPairName
          'publicKey' = $PublicKey
      })
    }
    If ($PSCmdlet.ShouldProcess('Create key pair'))
    {
      $keypair = Invoke-hRavelloRest @sKeyPair
      $keypair | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloKeyPair
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'KeyPairId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$KeyPairId,
    [Parameter(Mandatory = $True, ParameterSetName = 'KeyPairName')]
    [string]$KeyPairName,
    [string]$NewName,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($KeyPairName)
    {
      $KeyPairId = Get-RavelloKeyPair |
      Where-Object{$_.Name -eq $KeyPairName} |
      Select-Object -ExpandProperty id
    }
    $sKeyPair = @{
      Method  = 'Put'
      Request = "keypairs/$($KeyPairId)"
      Body    = @{
        'id' = $KeyPairId
        'name' = $NewName
      }
    }
    If ($PSCmdlet.ShouldProcess('Change key pair'))
    {
      $keypair = Invoke-hRavelloRest @sKeyPair
      $keypair | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloKeyPair
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'KeyPairId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$KeyPairId,
    [Parameter(Mandatory = $True, ParameterSetName = 'KeyPairName')]
    [string]$KeyPairName
  )
	
  process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($KeyPairName)
    {
      $KeyPairId = Get-RavelloKeyPair |
      Where-Object{$_.Name -eq $KeyPairName} |
      Select-Object -ExpandProperty id
    }
    $sKeyPair = @{
      Method  = 'Delete'
      Request = "keypairs/$($KeyPairId)"
    }
    If ($PSCmdlet.ShouldProcess('Remove key pair'))
    {Invoke-hRavelloRest @sKeyPair}
  }
}
#endregion

#region Elastic IPs
# .ExternalHelp Ravello-Help.xml
function Get-RavelloElasticIP
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sElasticIP = @{
      Method  = 'Get'
      Request = 'elasticIps'
    }
    If ($PSCmdlet.ShouldProcess('Get Elastic IPs'))
    {
      $eIP = Invoke-hRavelloRest @sElasticIP
      $eIP | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloElasticIP
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [ValidateScript({(Get-RavelloElasticIPLocation) -contains $_})]
    [string]$Location,
    [string]$Name,
    [string]$Description,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sElasticIP = @{
      Method  = 'Post'
      Request = 'elasticIps'
      Body    = @{
        location = $Location
      }
    }
    if($Name)
    {$sElasticIP.Body.Add('name',$Name)}
    if($Description)
    {$sElasticIP.Body.Add('description',$Description)}
        
    If ($PSCmdlet.ShouldProcess('Create elastic IP'))
    {
      $eIP = Invoke-hRavelloRest @sElasticIP
      $eIP | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloElasticIP
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName)]
    [Alias('ip')]
    [string]$ElasticIpAddress
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sElasticIP = @{
      Method  = 'Delete'
      Request = "elasticIps/$($ElasticIpAddress)"
    }
    If ($PSCmdlet.ShouldProcess('Remove elastic IP'))
    {Invoke-hRavelloRest @sElasticIP}
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloElasticIPLocation
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param ()

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sElasticIP = @{
      Method  = 'Get'
      Request = 'elasticIps/locations'
    }
    If ($PSCmdlet.ShouldProcess('Get elastic IP locations'))
    {Invoke-hRavelloRest @sElasticIP}
  }
}

#endregion

#region Organizations
# .ExternalHelp Ravello-Help.xml
function Get-RavelloOrganization
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'OrganizationId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$OrganizationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'OrganizationName')]
    [string]$OrganizationName,
    [Parameter(ParameterSetName = 'OrganizationName')]
    [Parameter(ParameterSetName = 'OrganizationId')]
    [switch]$Users = $false
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sOrg = @{
      Method  = 'Get'
      Request = 'organization'
    }
    if ($OrganizationName)
    {
      $OrganizationId = Get-RavelloOrganization |
      Where-Object{$_.organizationName -eq $OrganizationName} |
      Select-Object -ExpandProperty id
    }
    if ($OrganizationId)
    {
      if ($Users)
      {$sOrg.Request = $sOrg.Request.Replace('organization', "organizations/$([String]$OrganizationId)/users")}
      else
      {$sOrg.Request = $sOrg.Request.Replace('organization', "organizations/$([String]$OrganizationId)")}
    }
    If ($PSCmdlet.ShouldProcess('Get Organization'))
    {Invoke-hRavelloRest @sOrg}
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloOrganization
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'OrganizationId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$OrganizationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'OrganizationName')]
    [string]$OrganizationName,
    [Parameter(Mandatory = $True)]
    [string]$NewOrganizationName
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($OrganizationName)
    {
      $OrganizationId = Get-RavelloOrganization |
      Where-Object{$_.organizationName -eq $OrganizationName} |
      Select-Object -ExpandProperty id
    }
    $sOrganization = @{
      Method  = 'Put'
      Request = "organizations/$([String]$OrganizationId)"
      Body    = @{
        'organizationName' = $NewOrganizationName
      }
    }
    If ($PSCmdlet.ShouldProcess('Change organization'))
    {Invoke-hRavelloRest @sOrganization}
  }
}
#endregion

#region Users
# .ExternalHelp Ravello-Help.xml
function Get-RavelloUser
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$LastName,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$FirstName,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$UserId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AllUsers')]
    [switch]$All = $false,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sUser = @{
      Method = 'Get'
    }
    if (($FirstName -and $LastName) -or ($UserId -ne 0))
    {$All = $True}
    if ($All)
    {$sUser.Add('Request', 'users')}
    else
    {$sUser.Add('Request', 'user')}
    If ($PSCmdlet.ShouldProcess('Get users'))
    {
      $Users = Invoke-hRavelloRest @sUser
      if ($UserId -ne 0)
      {
        $Users = $Users | Where-Object{$_.id -eq $UserId}
      }
      if ($FirstName -and $LastName)
      {
        $Users = $Users | Where-Object{"$($_.name) $($_.surname)" -eq "$($FirstName) $($LastName)"}
      }
      $Users | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloUser
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'OrganizationId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$OrganizationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'OrganizationName')]
    [string]$OrganizationName,
    [Parameter(Mandatory = $True)]
    [string]$EmailAddress,
    [Parameter(Mandatory = $True)]
    [string]$LastName,
    [Parameter(Mandatory = $True)]
    [string]$FirstName,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($OrganizationName)
    {
      $OrganizationId = Get-RavelloOrganization |
      Where-Object{$_.organizationName -eq $OrganizationName} |
      Select-Object -ExpandProperty id
    }
    # New users are added by default to the Users group
    $pg = Get-RavelloPermissionsGroup -PermissionGroupName User
    $sUser = @{
      Method  = 'Post'
      Request = 'users/invite'
      Body    = @{
        email               = $EmailAddress
        lastName            = $LastName
        firstName           = $FirstName
        permissionGroupsSet = @($pg.Id)
      }
    }
    If ($PSCmdlet.ShouldProcess('Create user'))
    {
      $Users = Invoke-hRavelloRest @sUser
      $Users | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

<# Open issue 12580
    # .ExternalHelp Ravello-Help.xml
    function Set-RavelloUser
    {
    [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
    param (
    [Parameter(Mandatory = $True, ParameterSetName = 'UserId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$UserId,
    [string]$NewFirstName,
    [string]$NewLastName,
    [string]$NewEmailAddress,
    [string[]]$NewRoles,
    [Parameter(DontShow)]
    [switch]$Raw
    )
	
    Process
    {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $user = Get-RavelloUser -UserId $UserId
    $sUser = @{
    Method  = 'Put'
    Request = "users/$($UserId)"
    Body    = @{
    id = $user.id
    nickname = $user.nickname
    name = $user.name
    surname = $user.surname
    roles = $user.roles
    }
    }
    if($NewEmailAddress)
    {
    $sUser.Body.email = $NewEmailAddress
    }
    if($NewFirstName)
    {
    $sUser.Body.name = $NewFirstName
    }
    if($NewLastName)
    {
    $sUser.Body.surname = $NewLastName
    }
    if($NewRoles)
    {
    $sUser.Body.roles = $NewRoles
    }
    If ($PSCmdlet.ShouldProcess('Change user'))
    {
    $User = Invoke-hRavelloRest @sUser
    $User | ForEach-Object{
    if(!$Raw)
    {
    Convert-hRavelloTimeField -Object $_
    }
    $_
    }
    }
    }
    }
#>

# .ExternalHelp Ravello-Help.xml
function Set-RavelloUserPassword
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'UserId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$UserId,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$LastName,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$FirstName,
    [Parameter(Mandatory = $True)]
    [string]$Password,
    [Parameter(Mandatory = $True)]
    [string]$NewPassword
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($LastName -and $FirstName)
    {
      $User = Get-RavelloUser -All | Where-Object{$_.name -eq $FirstName -and $_.surname -eq $LastName -and $_.email -eq $EmailAddress}
      $UserId = $User.id
    }
    else
    {
      $User = Get-RavelloUser | Where-Object{$_.id -eq $UserId}
    }
    $sUser = @{
      Method  = 'Put'
      Request = "users/$($UserId)/changepw"
      Body    = @{
        existingPassword = $Password
        newPassword      = $NewPassword
      }
    }
    If ($PSCmdlet.ShouldProcess('Change user password'))
    {Invoke-hRavelloRest @sUser}
  }
}

# .ExternalHelp Ravello-Help.xml
function Disable-RavelloUser
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'UserId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$UserId,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$LastName,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$FirstName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($LastName -and $FirstName)
    {
      $User = Get-RavelloUser -All | Where-Object{$_.name -eq $FirstName -and $_.surname -eq $LastName -and $_.email -eq $EmailAddress}
      $UserId = $User.id
    }
    $sUser = @{
      Method  = 'Put'
      Request = "users/$($UserId)/disable"
    }
    If ($PSCmdlet.ShouldProcess('Disable user'))
    {Invoke-hRavelloRest @sUser}
  }	
}

# .ExternalHelp Ravello-Help.xml
function Enable-RavelloUser
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'UserId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$UserId,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$LastName,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$FirstName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($LastName -and $FirstName)
    {
      $User = Get-RavelloUser -All | Where-Object{$_.name -eq $FirstName -and $_.surname -eq $LastName -and $_.email -eq $EmailAddress}
      $UserId = $User.id
    }
    $sUser = @{
      Method  = 'Put'
      Request = "users/$($UserId)/enable"
    }
    If ($PSCmdlet.ShouldProcess('Enable user'))
    {Invoke-hRavelloRest @sUser}
  }	
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloUser
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'UserId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$UserId,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$LastName,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$FirstName
  )
    
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($LastName -and $FirstName)
    {
      $User = Get-RavelloUser -All | Where-Object{$_.name -eq $FirstName -and $_.surname -eq $LastName -and $_.email -eq $EmailAddress}
      $UserId = $User.id
    }
    $sUser = @{
      Method  = 'Delete'
      Request = "users/$($UserId)"
    }
    If ($PSCmdlet.ShouldProcess('Remove user'))
    {Invoke-hRavelloRest @sUser}
    
  }	
}
#endregion

#region Shares
# .ExternalHelp Ravello-Help.xml
function Get-RavelloShare
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [long]$ShareId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ShareUserName')]
    [string]$SharingUserFirstName,
    [Parameter(Mandatory = $True, ParameterSetName = 'ShareUserName')]
    [string]$SharingUserLastName,
    [Parameter(Mandatory = $True, ParameterSetName = 'ShareUserId')]
    [Alias('id')]
    [long]$SharingUserId,
    [string]$TargetEmail,
    [ValidateSet('BLUEPRINT','LIBRARY_VM','DISK_IMAGE')]
    [string]$ResourceType,
    [string]$SharedResourceName,
    [long]$SharedResourceId,
    [Parameter(DontShow)]
    [switch]$Raw
  )
    
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sShare = @{
      Method  = 'Get'
      Request = 'shares'
    }
    $q = @()
    if($SharedResourceName)
    {
      $shr = Get-RavelloShare | Where-Object{$_.name -eq $SharedResourceName}
      $SharedResourceId = $shr.id
    }
    if ($SharedResourceId -ne 0)
    {$q += "sharedResourceId=$($SharedResourceId)"}
    if($SharingUserFirstName -and $SharingUserLastName)
    {
      $User = Get-RavelloUser -FirstName $SharingUserFirstName -LastName $SharingUserLastName
      $SharingUserId = $User.id
    }
    if($SharingUserId)
    {$q += "sharingUserId=$($SharingUserId)"}
    if($TargetEmail)
    {$q += "targetEmail=$($TargetEmail)"}
    if($ResourceType)
    {$q += "sharedResourceType=$($ResourceType)"}
    if($q)
    {$sShare.Request = $sShare.Request, ($q -join '&') -join '?'}
    If ($PSCmdlet.ShouldProcess('Get share'))
    {
      $shares = Invoke-hRavelloRest @sShare
      if($ShareId -ne 0)
      {
        $shares = $shares | Where-Object{$_.id -eq $ShareId}
      }
      $shares | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Grant-RavelloShare
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ShareResourceName')]
    [string]$SharedResourceName,
    [Parameter(Mandatory = $True, ParameterSetName = 'ShareResourceId')]
    [long]$SharedResourceId,
    [Parameter(Mandatory = $True)]
    [string]$TargetEmail,
    [Parameter(Mandatory = $True)]
    [ValidateSet('BLUEPRINT','LIBRARY_VM','DISK_IMAGE')]
    [string]$ResourceType
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if($SharedResourceName)
    {
      $SharedResourceId = switch($ResourceType)
      {
        'BLUEPRINT' 
        {
          Get-RavelloBlueprint -BlueprintName $SharedResourceName |
          Select-Object -ExpandProperty id
        }
        'LIBRARY_VM' 
        {
          Get-RavelloImage -ImageName $SharedResourceName |
          Select-Object -ExpandProperty id
        }
        'DISK_IMAGE' 
        {
          Get-RavelloDiskImage -DiskImageName $SharedResourceName |
          Select-Object -ExpandProperty id
        }
      }
    }
    $sShare = @{
      Method  = 'Post'
      Request = 'shares'
      Body    = @{
        targetEmail        = $TargetEmail
        sharedResourceType = $ResourceType
        sharedResourceId   = $SharedResourceId
      }
    }
    If ($PSCmdlet.ShouldProcess('Grant share access'))
    {Invoke-hRavelloRest @sShare}    
  }
}

# .ExternalHelp Ravello-Help.xml
function Revoke-RavelloShare
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ShareId
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sShare = @{
      Method  = 'Delete'
      Request = "shares/$($ShareId)"
    }
    If ($PSCmdlet.ShouldProcess('Revoke share access'))
    {Invoke-hRavelloRest @sShare}    
  }
}
#endregion

#region Communities
# .ExternalHelp Ravello-Help.xml
function Get-RavelloCommunity
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ComId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$CommunityId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ComName')]
    [string]$CommunityName
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sCom = @{
      Method  = 'Get'
      Request = 'communities'
    }
    if($CommunityName)
    {
      $com = Get-RavelloCommunity | Where-Object{$_.Name -eq $CommunityName}
      $CommunityId = $com.id
    }
    if($CommunityId)
    {$sCom.Request = $sCom.Request, "/$($CommunityId)" -join '/'}
    If ($PSCmdlet.ShouldProcess('Get community'))
    {
      $comm = Invoke-hRavelloRest @sCom
      if ($CommunityName)
      {
        $comm | Where-Object{$CommunityName -like $CommunityName}
      }
      else
      {$comm}
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloRepoBlueprint
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ComId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$CommunityId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ComName')]
    [string]$CommunityName,
    [Parameter(ParameterSetName = 'ComId')]
    [Parameter(ParameterSetName = 'ComName')]
    [long]$BlueprintId,
    [Parameter(ParameterSetName = 'ComId')]
    [Parameter(ParameterSetName = 'ComName')]
    [string]$BlueprintName
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($CommunityName)
    {
      $communities = Get-RavelloCommunity
      $CommunityId = $communities |
      Where-Object{$_.name -eq $CommunityName} |
      Select-Object -ExpandProperty id
    }
    $sRepo = @{
      Method  = 'Get'
      Request = "communities/$($CommunityId)/blueprints"
    }
    if ($BlueprintId -eq 0 -and !$BlueprintName)
    {$mask = '*'}
    elseif ($BlueprintName)
    {$mask = $BlueprintName}
    else
    {$mask = "^$"}
    If ($PSCmdlet.ShouldProcess('Get blueprint from Ravello Repo'))
    {
      $bp = Invoke-hRavelloRest @sRepo
      $bp |
      Where-Object{$_.id -eq $BlueprintId -or $_.Name -like $mask} |
      ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloRepoDisk
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ComId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$CommunityId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ComName')]
    [string]$CommunityName,
    [Parameter(ParameterSetName = 'ComId')]
    [Parameter(ParameterSetName = 'ComName')]
    [long]$DiskId,
    [Parameter(ParameterSetName = 'ComId')]
    [Parameter(ParameterSetName = 'ComName')]
    [string]$DiskName
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($CommunityName)
    {
      $communities = Get-RavelloCommunity
      $CommunityId = $communities |
      Where-Object{$_.name -eq $CommunityName} |
      Select-Object -ExpandProperty id
    }
    $sRepo = @{
      Method  = 'Get'
      Request = "communities/$($CommunityId)/diskImages"
    }
    if ($DiskId -eq 0 -and !$DiskName)
    {$mask = '*'}
    elseif ($DiskName)
    {$mask = $DiskName}
    else
    {$mask = "^$"}
    If ($PSCmdlet.ShouldProcess('Get disks from Ravello Repo'))
    {
      $disk = Invoke-hRavelloRest @sRepo
      $disk |
      Where-Object{$_.id -eq $DiskId -or $_.Name -like $mask} |
      ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloRepoVm
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'ComId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$CommunityId,
    [Parameter(Mandatory = $True, ParameterSetName = 'ComName')]
    [string]$CommunityName,
    [Parameter(ParameterSetName = 'ComId')]
    [Parameter(ParameterSetName = 'ComName')]
    [long]$VmId,
    [Parameter(ParameterSetName = 'ComId')]
    [Parameter(ParameterSetName = 'ComName')]
    [string]$VmName,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($CommunityName)
    {
      $communities = Get-RavelloCommunity
      $CommunityId = $communities |
      Where-Object{$_.name -eq $CommunityName} |
      Select-Object -ExpandProperty id
    }
    $sRepo = @{
      Method  = 'Get'
      Request = "communities/$($CommunityId)/images"
    }
    if ($VmId -eq 0 -and !$VmName)
    {$mask = '*'}
    elseif ($VmName)
    {$mask = $VmName}
    else
    {$mask = "^$"}
    If ($PSCmdlet.ShouldProcess('Get blueprint from Ravello Repo'))
    {
      $vm = Invoke-hRavelloRest @sRepo
      $vm |
      Where-Object{$_.id -eq $VmId -or $_.Name -like $mask} |
      ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Copy-RavelloRepoBlueprint
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'BpId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $True, ParameterSetName = 'BpName')]
    [string]$BlueprintName,
    [string]$NewBlueprintName,
    [string]$Description
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($BlueprintName)
    {
      $bp = Get-RavelloRepo | Get-RavelloRepoBlueprint -BlueprintName $BlueprintName
      $BlueprintId = $bp.id
    }
    elseif ($BlueprintId)
    {$bp = Get-RavelloRepo | Get-RavelloRepoBlueprint -BlueprintId $BlueprintId}
    if (!$Description)
    {$Description = "Copy of $($bp.name)"}
    $sRepo = @{
      Method  = 'Post'
      Request = 'blueprints'
      Body    = @{
        blueprintId   = $bp.id
        blueprintName = $NewBlueprintName
        description   = $Description
        clearKeyPairs = $True
        offline       = ([string]$Offline).ToLower()
      }
    }
    If ($PSCmdlet.ShouldProcess('Copy blueprint from Repo'))
    {Invoke-hRavelloRest @sRepo}
  }
}

# .ExternalHelp Ravello-Help.xml
function Copy-RavelloRepoDisk
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'DiskId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskId,
    [Parameter(Mandatory = $True, ParameterSetName = 'DiskName')]
    [string]$DiskName,
    [string]$NewDiskName,
    [string]$Description
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($DiskName)
    {
      $disk = Get-RavelloRepo | Get-RavelloRepoDisk -DiskName $DiskName
      $DiskId = $disk.id
    }
    elseif ($DiskId)
    {$disk = Get-RavelloRepo | Get-RavelloRepoDisk -DiskId $DiskId}
    if (!$Description)
    {$Description = "Copy of $($disk.name)"}
    $sRepo = @{
      Method  = 'Post'
      Request = 'diskImages'
      Body    = @{
        diskImage   = @{
          description = $Description
          name        = $NewDiskName
        }
        diskImageId = $disk.id
      }
    }
    If ($PSCmdlet.ShouldProcess('Copy disk from Repo'))
    {Invoke-hRavelloRest @sRepo}
  }
}

# .ExternalHelp Ravello-Help.xml
function Copy-RavelloRepoVm
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'VmId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$VmId,
    [Parameter(Mandatory = $True, ParameterSetName = 'VmName')]
    [string]$VmName,
    [string]$NewVmName,
    [string]$Description
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($VmName)
    {
      $vm = Get-RavelloRepo | Get-RavelloRepoVm -VmName $VmName
      $VmId = $vm.id
    }
    elseif ($VmId)
    {$vm = Get-RavelloRepo | Get-RavelloRepoVm -VmId $VmId}
    if (!$Description)
    {$Description = "Copy of $($vm.name)"}
    $sRepo = @{
      Method  = 'Post'
      Request = 'images'
      Body    = @{
        blueprint    = $false
        imageId      = $vm.id
        imageName    = $NewVmName
        clearKeyPair = $True
        offline      = $false
      }
    }
    If ($PSCmdlet.ShouldProcess('Copy VM from Repo'))
    {Invoke-hRavelloRest @sRepo}
  }
}
#endregion

#region Ephemeral Access Tokens
# .ExternalHelp Ravello-Help.xml
function Get-RavelloEphemeralAccessToken
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'TokenId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$EphemeralAccessTokenId,
    [Parameter(Mandatory = $True, ParameterSetName = 'TokenName')]
    [string]$EphemeralAccessTokenName,
    [Parameter(DontShow)]
    [switch]$Raw
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sTok = @{
      Method  = 'Get'
      Request = 'ephemeralAccessTokens'
    }
    if($EphemeralAccessTokenName)
    {
      $tok = Get-RavelloEphemeralAccessToken | Where-Object{$_.Name -eq $EphemeralAccessTokenName}
      $EphemeralAccessTokenId = $tok.id
    }
    if($EphemeralAccessTokenId)
    {$sTok.Request = $sTok.Request, "$($EphemeralAccessTokenId)" -join '/'}
    If ($PSCmdlet.ShouldProcess('Get ephemeral access token'))
    {
      $token = Invoke-hRavelloRest @sTok
      $token | 
      Where-Object{$_.name -match $EphemeralAccessTokenName} |
      ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloEphemeralAccessToken
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True)]
    [string]$EphemeralAccessTokenName,
    [DateTime]$ExpirationTime,
    [string]$Description,
    [PSObject[]]$Permissions
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sTok = @{
      Method  = 'Post'
      Request = 'ephemeralAccessTokens'
      Body    = @{
        name = $EphemeralAccessTokenName
      }
    }
    if($ExpirationTime)
    {$sTok.Body.Add('expirationTime', (ConvertTo-hRavelloJsonDateTime -Date $ExpirationTime))}
    if($Description)
    {$sTok.Body.Add('description', $Description)}
    if($Permissions)
    {$sTok.Body.Add('permissions', $Permissions)}
    If ($PSCmdlet.ShouldProcess('Create ephemeral access token'))
    {
      $token = Invoke-hRavelloRest @sTok
      if(!$Raw)
      {Convert-hRavelloTimeField -Object $token}
      $token
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloEphemeralAccessToken
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'TokenId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$EphemeralAccessTokenId,
    [Parameter(Mandatory = $True, ParameterSetName = 'TokenName')]
    [string]$EphemeralAccessTokenName,
    [string]$NewName,
    [DateTime]$NewExpirationTime,
    [string]$NewDescription,
    [PSObject[]]$NewPermissions,
    [Parameter(DontShow)]
    [switch]$Raw
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if($EphemeralAccessTokenName)
    {
      $token = Get-RavelloEphemeralAccessToken -EphemeralAccessTokenName $EphemeralAccessTokenName -Raw
      $EphemeralAccessTokenId = $token.id
    }
    else
    {$token = Get-RavelloEphemeralAccessToken -EphemeralAccessTokenId $EphemeralAccessTokenId -Raw}

    if(!$NewName)
    {$NewName = $token.name}
    if(!$NewDescription)
    {$NewDescription = $token.description}
    if(!$NewExpirationTime)
    {$NewExpirationTime = $token.expirationTime}
    if(!$NewPermissions)
    {$NewPermissions = $token.permissions}
    
    $sTok = @{
      Method  = 'Put'
      Request = "ephemeralAccessTokens/$($EphemeralAccessTokenId)"
      Body    = @{
        id          = $EphemeralAccessTokenId
        name        = $NewName
        description = $NewDescription
        permissions = $NewPermissions
      }
    }

    If ($PSCmdlet.ShouldProcess('Set ephemeral access token'))
    {
      $token = Invoke-hRavelloRest @sTok
      $token | 
      Where-Object{$_.name -match $EphemeralAccessTokenName} |
      ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloEphemeralAccessToken
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'TokenId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$EphemeralAccessTokenId,
    [Parameter(Mandatory = $True, ParameterSetName = 'TokenName')]
    [string]$EphemeralAccessTokenName
  )
    
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($EphemeralAccessTokenName)
    {
      $token = Get-RavelloEphemeralAccessToken -EphemeralAccessTokenName $EphemeralAccessTokenName
      $EphemeralAccessTokenId = $token.id
    }
    $sTok = @{
      Method  = 'Delete'
      Request = "ephemeralAccessTokens/$($EphemeralAccessTokenId)"
    }
    If ($PSCmdlet.ShouldProcess('Remove ephemeral access token'))
    {Invoke-hRavelloRest @sTok}
  }	
}
#endregion

#region Permissions
# .ExternalHelp Ravello-Help.xml
function Get-RavelloPermissionsGroup
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'PermissionGroupId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$PermissionGroupId,
    [Parameter(Mandatory = $True, ParameterSetName = 'PermissionGroupName')]
    [string]$PermissionGroupName,
    [Parameter(ParameterSetName = 'PermissionGroupId')]
    [Parameter(ParameterSetName = 'PermissionGroupName')]
    [switch]$Users,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserId')]
    [long]$UserId,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$LastName,
    [Parameter(Mandatory = $True, ParameterSetName = 'UserName')]
    [string]$FirstName,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sPGroup = @{
      Method  = 'Get'
      Request = 'permissionsGroups'
    }
    if ($PermissionGroupName)
    {
      $pg = Get-RavelloPermissionsGroup | Where-Object{$_.name -eq $PermissionGroupName}
      $PermissionGroupId = $pg.id
    }
    if ($PermissionGroupId)
    {$sPGroup.Request = $sPGroup.Request.Replace('permissionsGroups', "permissionsGroups/$([String]$PermissionGroupId)")}
    if ($Users)
    {$sPGroup.Request = $sPGroup.Request, 'users' -join '/'}
    if ($FirstName -and $LastName)
    {$UserId = Get-RavelloUser -FirstName $FirstName -LastName $LastName | Select-Object -ExpandProperty id}
    if ($UserId)
    {$sPGroup.Request = $sPGroup.Request.Replace('permissionsGroups', "permissionsGroups?userId=$([String]$UserId)")}
    If ($PSCmdlet.ShouldProcess('Get permissions group'))
    {
      $groups = Invoke-hRavelloRest @sPGroup
      $groups | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloPermissionsGroup
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True)]
    [string]$PermissionsGroupName,
    [string]$Description,
    [PSObject[]]$Permissions,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sPGroup = @{
      Method  = 'Post'
      Request = 'permissionsGroups'
      Body    = @{
        name        = $PermissionsGroupName
        description = $Description
        permissions = $Permissions
      }
    }
    If ($PSCmdlet.ShouldProcess('Create permissions group'))
    {
      $pg = Invoke-hRavelloRest @sPGroup
      $pg | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloPermissionsGroup
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'PermissionGroupId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$PermissionGroupId,
    [Parameter(Mandatory = $True, ParameterSetName = 'PermissionGroupName')]
    [string]$PermissionGroupName,
    [string]$NewName,
    [string]$NewDescription,
    [PSObject[]]$NewPermissions,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($PermissionGroupName)
    {
      $pg = Get-RavelloPermissionsGroup -PermissionGroupName $PermissionGroupName -Raw
      $PermissionGroupId = $pg.id
    }
    else
    {$pg = Get-RavelloPermissionsGroup -PermissionGroupId $PermissionGroupId -Raw}
    $sPGroup = @{
      Method  = 'Put'
      Request = "permissionsGroups/$($PermissionGroupId)"
      Body    = $pg
    }
    if ($NewName)
    {$sPGroup.Body.name = $NewName}
    if ($NewDescription)
    {$sPGroup.Body.description = $NewDescription}
    if ($NewPermissions)
    {$sPGroup.Body.permissions = $NewPermissions}
    #    $sPGroup.Body.creationTime = ConvertTo-hRavelloJsonDateTime -Date $sPGroup.Body.creationTime
    If ($PSCmdlet.ShouldProcess('Change permissions group'))
    {
      $pg = Invoke-hRavelloRest @sPGroup
      $pg | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Add-RavelloPermissionsGroupUser
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'PGId-UName', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'PGId-UId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$PermissionGroupId,
    [Parameter(Mandatory = $True, ParameterSetName = 'PGName-UName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'PGName-UId')]
    [string]$PermissionGroupName,
    [Parameter(Mandatory = $True, ParameterSetName = 'PGId-UId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'PGName-UId')]
    [long]$UserId,
    [Parameter(Mandatory = $True, ParameterSetName = 'PGId-UName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'PGName-UName')]
    [string]$FirstName,
    [Parameter(Mandatory = $True, ParameterSetName = 'PGId-UName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'PGName-UName')]
    [string]$LastName,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($PermissionGroupName)
    {
      $pg = Get-RavelloPermissionsGroup -PermissionGroupName $PermissionGroupName
      $PermissionGroupId = $pg.id
    }
    else
    {$pg = Get-RavelloPermissionsGroup -PermissionGroupId $PermissionGroupId}
    if ($FirstName -and $LastName)
    {
      $User = Get-RavelloUser -FirstName $FirstName -LastName $LastName
      $UserId = $User.id
    }
    $sPGroup = @{
      Method  = 'Post'
      Request = "permissionsGroups/$($PermissionGroupId)/users"
      Body    = @{
        userId = $UserId
      }
    }
    If ($PSCmdlet.ShouldProcess('Add user to permissions group'))
    {
      $pg = Invoke-hRavelloRest @sPGroup
      $pg | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloPermissionsGroup
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'PgId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'PgId-UId', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'PgId-UName', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$PermissionGroupId,
    [Parameter(Mandatory = $True, ParameterSetName = 'PgName', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $True, ParameterSetName = 'PgName-UId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'PgName-UName')]
    [string]$PermissionGroupName,
    [Parameter(Mandatory = $True, ParameterSetName = 'PgId-UId')]
    [Parameter(Mandatory = $True, ParameterSetName = 'PgName-UId')]
    [long]$UserId,
    [Parameter(Mandatory = $True, ParameterSetName = 'PgId-UName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'PgName-UName')]
    [string]$FirstName,
    [Parameter(Mandatory = $True, ParameterSetName = 'PgId-UName')]
    [Parameter(Mandatory = $True, ParameterSetName = 'PgName-UName')]
    [string]$LastName,
    [Parameter(DontShow)]
    [switch]$Raw
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($PermissionGroupName)
    {
      $pg = Get-RavelloPermissionsGroup -PermissionGroupName $PermissionGroupName
      $PermissionGroupId = $pg.id
    }
    $sPGroup = @{
      Method  = 'Delete'
      Request = "permissionsGroups/$($PermissionGroupId)"
    }
    if (($FirstName -and $LastName) -or ($UserId -ne 0))
    {
      if ($FirstName -and $LastName)
      {
        $User = Get-RavelloUser -FirstName $FirstName -LastName $LastName
        $UserId = $User.id
      }
      $sPGroup.Request = $sPGroup.Request, 'users', "$($UserId)" -join '/'
    }
    If ($PSCmdlet.ShouldProcess('Remove permissions group'))
    {
      $groups = Invoke-hRavelloRest @sPGroup
      $groups | ForEach-Object{
        if(!$Raw)
        {Convert-hRavelloTimeField -Object $_}
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloPermissionDescriptor
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [ValidateScript({(Get-RavelloPermissionDescriptor).resourceType -contains $_})]
    [string[]]$ResourceType
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sPGroup = @{
      Method  = 'Get'
      Request = 'permissionsGroups/describe'
    }
    If ($PSCmdlet.ShouldProcess('Get permission descriptors'))
    {
      $descriptors = Invoke-hRavelloRest @sPGroup
      if($ResourceType)
      {
        $descriptors | Where-Object{$ResourceType -contains $_.resourceType}
      }
      else
      {$descriptors}
    }
  }
}
#endregion

#region Notifications
# .ExternalHelp Ravello-Help.xml
function Get-RavelloNotification
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low',DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'AppId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $True, ParameterSetName = 'AppName', ValueFromPipelineByPropertyName)]
    [string]$ApplicationName,
    [ValidateSet('INFO','TRACE','WARN','ERROR')]
    [string]$NotificationLevel,
    [long]$MaxResults,
    [DateTime]$Start,
    [DateTime]$Finish
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sNotification = @{
      Method  = 'Post'
      Request = 'notifications/search'
      Body    = @{ }
    }
		
    if ($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      if ($app)
      {$ApplicationId = $app.id}
    }
    if ($ApplicationId)
    {$sNotification.Body.Add('appId', $ApplicationId)}
    if ($NotificationLevel)
    {$sNotification.Body.Add('notificationLevel', $NotificationLevel)}
    if ($MaxResults)
    {$sNotification.Body.Add('maxResults', $MaxResults)}
    if ($Start -or $Finish)
    {
      $dtObj = @{}
      if($Start)
      {$dtObj.Add('startTime',(ConvertTo-hRavelloJsonDateTime -Date $Start.ToLocalTime()))}
      else
      {$dtObj.Add('startTime',(ConvertTo-hRavelloJsonDateTime -Date (Get-Date -Date '1/1/1970').ToLocalTime()))}
      if($Finish)
      {$dtObj.Add('endTime',(ConvertTo-hRavelloJsonDateTime -Date $Finish.ToLocalTime()))}
      else
      {$dtObj.Add('endTime',(ConvertTo-hRavelloJsonDateTime -Date (Get-Date).ToLocalTime()))}
      $sNotification.Body.Add('dateRange', $dtObj)
    }
    If ($PSCmdlet.ShouldProcess('Get notifications'))
    {
      $notifications = Invoke-hRavelloRest @sNotification
      if(!$Raw)
      {Convert-hRavelloTimeField -Object $notifications}
      $notifications
    }
  }
}
#endregion

#region User Alerts
# .ExternalHelp Ravello-Help.xml
function Get-RavelloUserAlert
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param ()
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sUAlert = @{
      Method  = 'Get'
      Request = 'userAlerts'
    }
		
    If ($PSCmdlet.ShouldProcess('Get user alerts'))
    {Invoke-hRavelloRest @sUAlert}
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloUserAlert
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
  param (
    [Parameter(Mandatory = $True)]
    [ValidateScript({(Get-RavelloEvent) -contains $_})]
    [string]$EventName,
    [Parameter(ParameterSetName = 'UserId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$UserId,
    [Parameter(ParameterSetName = 'UserName')]
    [string]$FirstName,
    [Parameter(ParameterSetName = 'UserName')]
    [string]$LastName
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    if ($FisrName -and $LastName)
    {
      $User = Get-RavelloUser -FirstName $FirstName -LastName $LastName
      $UserId = $User.id
    }
    $sUAlert = @{
      Method  = 'Post'
      Request = 'userAlerts'
      Body    = @{
        'eventName' = $EventName
      }
    }
    if ($UserId)
    {$sUAlert.Body.Add('userId', $UserId)}
    If ($PSCmdlet.ShouldProcess('Change user alerts'))
    {Invoke-hRavelloRest @sUAlert}
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloUserAlert
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'High')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'UserId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$EventId
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sUAlert = @{
      Method  = 'Delete'
      Request = "userAlerts/$($EventId)"
    }
    If ($PSCmdlet.ShouldProcess('Remove user alert'))
    {Invoke-hRavelloRest @sUAlert}
  }
}
#endregion

#region Events
# .ExternalHelp Ravello-Help.xml
function Get-RavelloEvent
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param ()
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sEvent = @{
      Method  = 'Get'
      Request = 'events'
    }
    If ($PSCmdlet.ShouldProcess('Get events'))
    {Invoke-hRavelloRest @sEvent}
  }
}
#endregion

#region Billing
# .ExternalHelp Ravello-Help.xml
function Get-RavelloBilling
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param (
    [string]$Year = [string](Get-Date).AddMonths(-1).Year,
    [string]$Month = '{0:D2}' -f ((Get-Date).AddMonths(-1).Month)
  )
	
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sBill = @{
      Method  = 'Get'
      Request = 'billing'
    }
    if ($Year -and $Month)
    {$sBill.Request = $sBill.Request.Replace('billing', "billing?year=$('{0:D4}' -f [int]$Year)&month=$('{0:D2}' -f [int]$Month)")}
    If ($PSCmdlet.ShouldProcess('Get billing'))
    {Invoke-hRavelloRest @sBill}
  }
}
#endregion

#region Extra
# .ExternalHelp Ravello-Help.xml
function New-RavelloPermissionFilter
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param(
    [string]$Property,
    [string]$Operator,
    [string]$Operand
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    New-Object -TypeName PSObject -Property @{
      type         = 'SIMPLE'
      operator     = $Operator
      propertyName = $Property
      operand      = $Operand
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloPermission
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low')]
  param(
    [Parameter(Mandatory = $True)]
    [ValidateScript({(Get-RavelloPermissionDescriptor).resourceType -contains $_})]
    [string]$ResourceType,
    [Parameter(Mandatory = $True)]
    [string[]]$Action,
    [ValidateSet('And','Or')]
    [string]$FilterOperand = 'Or',
    [PSObject[]]$Filter
  )

  Process
  {
    $perm = New-Object -TypeName PSObject -Property @{
      resourceType = $ResourceType
      actions      = $Action
    }
    if($Filter)
    {
      $crit = New-Object -TypeName PSObject -Property @{
        type     = 'COMPLEX'
        operator = $FilterOperand
        criteria = $Filter
      }
      Add-Member -InputObject $perm -Name 'filterCriterion' -Value $crit -MemberType NoteProperty
    }
    $perm
  }
}

function Get-RavelloEphemeralTokenURL
{
  [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Low', DefaultParameterSetName = 'Default')]
  param (
    [Parameter(Mandatory = $True, ParameterSetName = 'TokenId', ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$EphemeralAccessTokenId,
    [Parameter(Mandatory = $True, ParameterSetName = 'TokenName')]
    [string]$EphemeralAccessTokenName
  )
    
  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $copyParms = $PSBoundParameters
    $token = Get-RavelloEphemeralAccessToken @copyParms
    $url = New-Object -TypeName PSObject -Property @{
      EndUser   = ''
      RavelloUI = "https://cloud.ravellosystems.com/#/$($token.token)"
    }
    $apps = $token.permissions | Where-Object{$_.ResourceType -eq 'APPLICATION'}
    if(($apps | Measure-Object).Count -eq 1)
    {
      $appId = $apps.filterCriterion.criteria.operand
      $url.EndUser = "https://access.ravellosystems.com/simple/#/$($token.token)/apps/$($appId)"
    }
    $url        
  }
}
#endregion

#region Usage
# .ExternalHelp Ravello-Help.xml
function Get-RavelloUsage
{
  [CmdletBinding(SupportsShouldProcess = $True,ConfirmImpact = 'Low')]
  param()

  Process{
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    Write-Verbose -Message "`t$($PSCmdlet.ParameterSetName)"
    Write-Verbose -Message "`tCalled from $($stack = Get-PSCallStack; $stack[1].Command) at $($stack[1].Location)"

    $sEvent = @{
      Method  = 'Get'
      Request = 'limits'
    }
    If ($PSCmdlet.ShouldProcess('List Usage'))
    {(Invoke-hRavelloRest @sEvent).Limitation}
  }
}
#endregion

#region Usage
# .ExternalHelp Ravello-Help.xml
function Get-RavelloUsage
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param()

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sEvent = @{
      Method  = 'Get'
      Request = 'limits'
    }
    If ($PSCmdlet.ShouldProcess("List Usage"))
    {
      (Invoke-RavRest @sEvent).Limitation
    }
  }
}
#endregion