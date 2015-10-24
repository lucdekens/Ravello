#region Module variables
$RavelloBaseUrl = 'https://cloud.ravellosystems.com/api/v1'
#endregion

#region Helpers
# .ExternalHelp Ravello-Help.xml
function ConvertFrom-JsonDateTime
{
  [CmdletBinding()]
  param(
    [string]$DateTime
  )

  Process{
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    (New-Object DateTime(1970, 1, 1, 0, 0, 0, 0)).AddMilliseconds([long]$DateTime).ToLocalTime()
  }
}

# .ExternalHelp Ravello-Help.xml
function ConvertTo-JsonDateTime
{
  [CmdletBinding()]
  param(
    [DateTime]$Date
  )

  Process
  {
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"
    [int64](($Date).addhours((([datetime]::UtcNow)-($Date)).Hours)-(Get-Date '1/1/1970')).totalmilliseconds
  }
}

# .ExternalHelp Ravello-Help.xml
function Invoke-RavRest
{
  [CmdletBinding()]
  param(
    [String]$Method,
    [String]$Request,
    [PSObject]$Body
  )

  Process{
    Write-Verbose -Message "$($MyInvocation.MyCommand.Name)"

    $headers = $Script:AuthHeader.Clone()
    $headers.Add('Accept','application/json')
    $sRest = @{
      Uri         = $RavelloBaseUrl, $Request -join '/'
      Method      = $Method
      ContentType = 'application/json'
      Headers     = $local:headers
      ErrorAction = 'Stop'
#      OutFile = 'C:\Temp\restmethod.txt'
#      PassThru = $true
    }
    if(Get-Process -Name fiddler -ErrorAction SilentlyContinue)
    {
      $sRest.Add('Proxy','http://127.0.0.1:8888')
    }
    if($Script:RavelloSession)
    {
      $sRest.Add('WebSession',$Script:RavelloSession)
    }
    else
    {
      $sRest.Add('SessionVariable','Script:RavelloSession')
    }
    # To handle nested properties the Depth parameter is used explicitely (default is 2)
    if($Body)
    {
      $sRest.Add('Body',($Body | ConvertTo-Json -Depth 32 -Compress))
    }

    Write-Debug -Message 'sRest==>'
    Write-Debug -Message "`tUri             : $($sRest.Uri)"
    Write-Debug -Message "`tMethod          : $($sRest.Method)"
    Write-Debug -Message "`tContentType     : $($sRest.ContentType)"
    Write-Debug -Message "`tHeaders"
    $sRest.Headers.GetEnumerator() |ForEach-Object -Process {
      Write-Debug "`t                : $($_.Name)`t$($_.Value)"
    }
    Write-Debug -Message "`tBody            : $($sRest.Body)"
    Write-Debug -Message "`tSessionVariable : $($sRest.SessionVariable)"
    Write-Debug -Message "`tSession         : $($sRest.Session)"

    # The intermediate $result is used to avoid returning a PSMemberSet
    Try
    {
      $result = Invoke-RestMethod @sRest
    }
    Catch
    {
      Write-Debug 'Invoke-RestMethod exception'
      Write-Debug "`tCode = $([int]$_.Exception.Response.StatusCode)"
      Write-Debug "`tMsg  = $($_.Exception.Response.StatusDescription)"
      Throw "$([int]$_.Exception.Response.StatusCode) $($_.Exception.Response.StatusDescription)"
    }
    $result
    Write-Debug 'Leaving Invoke-RavRest'
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-AuthHeader
{
  [CmdletBinding()]
  param()
  
  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    
    $User = $Script:RavelloCredential.UserName
    $Password = $Script:RavelloCredential.GetNetworkCredential().password
    Write-Verbose "`tUser: $($User)"

    $Encoded = [System.Text.Encoding]::UTF8.GetBytes(($User, $Password -Join ':'))
    $EncodedPassword = [System.Convert]::ToBase64String($Encoded)
    Write-Debug "`tEncoded  : $($EncodedPassword)"
    
    @{
      'Authorization' = "Basic $($EncodedPassword)"
    }
  }
}
#endregion

#region Import
# .ExternalHelp Ravello-Help.xml
function Import-Ravello
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [string]$CliPath = 'C:\Ravello_cli',
    [Parameter(Mandatory = $true,ParameterSetName = 'ISO')]
    [string]$IsoPath,
    [Parameter(Mandatory = $true,ParameterSetName = 'VM')]
    [string]$VmPath,
    [Parameter(Mandatory = $true,ParameterSetName = 'vSphere')]
    [string]$EsxVmPath,
    [Parameter(Mandatory = $true,ParameterSetName = 'vSphere')]
    [string]$EsxServer,
    [Parameter(Mandatory = $true,ParameterSetName = 'vSphere')]
    [System.Management.Automation.PSCredential]$EsxCredential,
    [Parameter(Mandatory = $true,ParameterSetName = 'vDisk')]
    [string]$DiskPath
  )

  Begin{
    $cmd = '#clipath#\ravello.exe #importtype# -u #user#'
  }

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"

    if(!(Test-Path -Path "$CliPath\ravello.exe"))
    {
      Write-Error "Could not find ravello.exe in $($CliPath)"
    }
    else
    {
      if(!$Script:RavelloCredential)
      {
        Write-Error 'You need to connect to Ravello before uploading files'
      }
      else
      {
        $User = $Script:RavelloCredential.UserName
        $pswd = $Script:RavelloCredential.GetNetworkCredential().password

        $oldRPswd = Get-Item -Path "Env:$($rPswd)" -ErrorAction SilentlyContinue
        $env:RAVELLO_PASSWORD = $pswd

        $cmd = $cmd.Replace('#clipath#',$CliPath)
        $cmd = $cmd.Replace('#user#',$User)

        if($PSCmdlet.ParameterSetName -eq 'ISO')
        {
          if(Test-Path -Path $IsoPath)
          {
            $cmd = $cmd.Replace('#importtype#','import-disk')
            $cmd = $cmd, $IsoPath -join ' '
          }
          else
          {
            Write-Error "Can't find ISO file $($IsoPath)"
          }
        }
        else
        {
          $cmd = $cmd.Replace('#importtype#','import')
          if($PSCmdlet.ParameterSetName -eq 'VM')
          {
            if(Test-Path -Path $VmPath)
            {
              $cmd = $cmd, $VmPath -join ' '
            }
            else
            {
              Write-Error "Can't find VM file $($VmPath)"
            }
          }
          elseif($PSCmdlet.ParameterSetName -eq 'vSphere')
          {
            $vUser = $EsxCredential.UserName
            $vPswd = $EsxCredential.GetNetworkCredential().password

            $cmd = $cmd, 
            '--vm_configuration_file_path', """$($EsxVmPath)""", 
            '--server_username', $vUser, 
            '--server_password', $vPswd, 
            '--server_address', $EsxServer -join ' '
          }
          elseif($PSCmdlet.ParameterSetName -eq 'vDisk')
          {
            if(Test-Path -Path $DiskPath)
            {
              $cmd = $cmd, '--disk', $DiskPath -join ' '
            }
            else
            {
              Write-Error "Can't find VMDK file $($DiskPath)"
            }
          }
        }

        Write-Verbose "$($cmd)"

        If ($PSCmdlet.ShouldProcess("Importing with $($cmd)"))
        {
            $result = Invoke-Expression -Command $cmd
            if(!($result -notmatch 'upload.finished.successfully'))
            {
              Write-Warning 'Upload might have failed - check the log'
            }
    
            Write-Verbose "$($result)"
        }
        if($oldRPswd)
        {
          $env:RAVELLO_PASSWORD = $oldRPswd
        }
        else
        {
          Remove-Item Env:\RAVELLO_PASSWORD
        }
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloImportHistory
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [string]$CliPath = 'C:\Ravello_cli'
  )

  Begin
  {
    $cmd = '#clipath#\ravello.exe list -y'
    $pattern = 'name:\s(?<Filename>.+)\s+id:\s(?<Id>\d+)\s+creation time:\s(?<Date>[^\n\r]+)\s+.+ (?<Perc>\d+)%'
  }

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"

    if(!(Test-Path -Path "$CliPath\ravello.exe"))
    {
      Write-Error "Could not find ravello.exe in $($CliPath)"
    }
    else
    {
      $cmd = $cmd.Replace('#clipath#',$CliPath)
      If ($PSCmdlet.ShouldProcess("Listing import jobs with $($cmd)"))
      {
          Invoke-Expression -Command $cmd |
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
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,
        ValueFromPipeline = $true,
    ParameterSetName = 'Credential')]
    [System.Management.Automation.PSCredential]$Credential,
    [Parameter(Mandatory = $true,
    ParameterSetName = 'PlainText')]
    [String]$User,
    [Parameter(Mandatory = $true,
    ParameterSetName = 'PlainText')]
    [String]$Password,
    [string]$Proxy
  )
  
  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($Proxy)
    {
        $PSDefaultParameterValues = @{
            'Invoke-RestMethod:Proxy'    = 'http://proxy.mas.eurocontrol.int:8080'
            '*:ProxyUseDefaultCredentials' = $true
        }
    }
    if($PSCmdlet.ParameterSetName -eq 'PlainText')
    {
      $sPswd = ConvertTo-SecureString -String $Password -AsPlainText -Force
      $Script:RavelloCredential = New-Object System.Management.Automation.PSCredential ($User, $sPswd)
    }
    if($PSCmdlet.ParameterSetName -eq 'Credential')
    {
      $Script:RavelloCredential = $Credential
    }
    $Script:AuthHeader = Get-AuthHeader
    If ($PSCmdlet.ShouldProcess("Connecting to Ravello"))
    {
        Invoke-RavRest -Method Post -Request 'login'
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Disconnect-Ravello
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param()
  
  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    If ($PSCmdlet.ShouldProcess("Disconnecting from Ravello"))
    {
        Invoke-RavRest -Method Post -Request 'logout'
    
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
function Get-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low',DefaultParameterSetName="Default")]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmAll')]
    [Parameter(ParameterSetName = 'Default')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId-VmAll')]
    [Parameter(ParameterSetName = 'Default')]
    [Alias('id')]
    [long]$ApplicationId,
    [Switch]$Design,
    [Switch]$Deployment,
    [Switch]$Properties,
    [Parameter(ParameterSetName = 'AppId-VmAll')]
    [Parameter(ParameterSetName = 'AppName-VmAll')]
    [Switch]$AllVm,
    [Parameter(ParameterSetName = 'AppId-VmName')]
    [Parameter(ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(ParameterSetName = 'AppId-VmId')]
    [Parameter(ParameterSetName = 'AppName-VmId')]
    [long]$VmId,
    [Parameter(DontShow)]
    [switch]$Raw
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    Write-Verbose "$($PSCmdlet.ParameterSetName)"
    $sApp = @{
      Method  = 'Get'
      Request = 'applications'
    }

    if($ApplicationName)
    {
      $ApplicationId = Get-RavelloApplication |
      Where-Object{
        $_.Name -eq $ApplicationName
      } |
      Select-Object -ExpandProperty id
    }
    if($ApplicationId -ne 0)
    {
      $sApp.Request = $sApp.Request, "$([string]$ApplicationId)" -join '/'

      if($Design)
      {
        $sApp.Request = $sApp.Request, 'design' -join ';'
      }
      if($Deployment)
      {
        $sApp.Request = $sApp.Request, 'deployment' -join ';'
      }
      if($Properties)
      {
        $sApp.Request = $sApp.Request, 'properties' -join ';'
      }

      if($VmName)
      {
        $app = Get-RavelloApplication -ApplicationId $ApplicationId -Design
        $VmId = $app.design.vms |
        Where-Object{
          $_.name -eq $VmName
        } |
        Select-Object -ExpandProperty id                
      }
      if($VmId)
      {
        $sApp.Request = $sApp.Request, 'vms', "$([string]$VmId)" -join '/'
      }
      if($AllVm)
      {
        $sApp.Request = $sApp.Request, 'vms' -join '/'
      }
  
      If ($PSCmdlet.ShouldProcess("Connecting to Ravello"))
      {
          $application = Invoke-RavRest @sApp
          $application | ForEach-Object{
            if(!$Raw)
            {
                $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
                if($_.nextStopTime)
                {
                  $_.nextStopTime = ConvertFrom-JsonDateTime -DateTime $_.nextStopTime
                }
                if($_.deployment)
                {
                  if($_.deployment.expirationTime)
                  {
                    $_.deployment.expirationTime = ConvertFrom-JsonDateTime -DateTime $_.deployment.expirationTime
                  }
                  if($_.deployment.publishStartTime)
                  {
                    $_.deployment.publishStartTime = ConvertFrom-JsonDateTime -DateTime $_.deployment.publishStartTime
                  }
                }
            }
          $_
        }
      }
    }
    elseif($PSCmdlet.ParameterSetName -eq 'Default' -and !$ApplicationName)
    {
      $application = Invoke-RavRest @sApp

      $application | ForEach-Object{
        if(!$Raw)
        {
        $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
        if($_.nextStopTime)
        {
          $_.nextStopTime = ConvertFrom-JsonDateTime -DateTime $_.nextStopTime
        }
        if($_.deployment)
        {
          if($_.deployment.expirationTime)
          {
            $_.deployment.expirationTime = ConvertFrom-JsonDateTime -DateTime $_.deployment.expirationTime
          }
          if($_.deployment.publishStartTime)
          {
            $_.deployment.publishStartTime = ConvertFrom-JsonDateTime -DateTime $_.deployment.publishStartTime
          }
        }
      }
        $_
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
#    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmId')]
#    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmName')]
#    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmId')]
#    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmName')]
    [Parameter(Mandatory = $true)]
    [string]$ApplicationName,
#    [Parameter(ParameterSetName = 'BpId-VmId',ValueFromPipelineByPropertyName)]
#    [Parameter(ParameterSetName = 'BpId-VmName',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
#    [Parameter(ParameterSetName = 'BpName-VmId')]
#    [Parameter(ParameterSetName = 'BpName-VmName')]
    [string]$BlueprintName,
#    [Parameter(ParameterSetName = 'BpId-VmId')]
#    [Parameter(ParameterSetName = 'BpName-VmId')]
    [long[]]$VmImageId,
#    [Parameter(ParameterSetName = 'BpId-VmName')]
#    [Parameter(ParameterSetName = 'BpName-VmName')]
    [string[]]$VmImageName,
    [string]$Description
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    # Create minimal Application
    $sApp = @{
      Method  = 'Post'
      Request = 'applications'
      Body    = @{
        name        = $ApplicationName
        description = $Description
      }
    }
    If ($PSCmdlet.ShouldProcess("Create application"))
    {
        $app = Invoke-RavRest @sApp
        # Customise with Set-RavelloApplication
        $sApp2 = @{}
        $PSBoundParameters.GetEnumerator() |
        Where-Object{
          $_.Key -notmatch '^Description|^ApplicationName'
        } |
        ForEach-Object{
          $sApp2.Add($_.Key,$_.Value)
        }
        if($sApp2.Count -gt 0)
        {
            $app | Set-RavelloApplication @sApp2
        }
        else
        {
          $app
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName')]
    [string]$ApplicationName,
    [Parameter(ParameterSetName = 'BlueprintId')]
    [long]$BlueprintId,
    [Parameter(ParameterSetName = 'BlueprintName')]
    [string]$BlueprintName,
    [Parameter(ParameterSetName = 'AppId-VmId')]
    [Parameter(ParameterSetName = 'AppName-VmId')]
    [long[]]$VmImageId,
    [Parameter(ParameterSetName = 'AppId-VmName')]
    [Parameter(ParameterSetName = 'AppName-VmName')]
    [string[]]$VmImageName,
    [Alias('Name')]
    [string]$NewApplicationName,
    [string]$Description
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($BlueprintName)
    {
      $BlueprintId = Get-RavelloBlueprint -Name $BlueprintName | Select-Object -ExpandProperty id
    }
    if($BlueprintId)
    {
      $sApp.Body.Add('baseBlueprintId',$BlueprintId)
    }
    if($ApplicationName)
    {
      $app = Get-RavelloApplication -Raw | Where-Object{
        $_.Name -eq $ApplicationName
      }
      $ApplicationId = $app.id
    }
    else
    {
      $app = Get-RavelloApplication -ApplicationId $ApplicationId -Raw
    }
    $sApp = @{
      Method  = 'Put'
      Request = "applications/$($ApplicationId)"
      Body    = $app
    }
    if($NewApplicationName)
    {
      $sApp.Body.name = $NewApplicationName
    }

    if($Description)
    {
      $sApp.Body.description = $Description
    }

    if($VmImageName -or $VmImageId)
    {
      $img = @()
      if($VmImageName)
      {
        $VmImageName | ForEach-Object{
          $img += Get-RavelloImage -Name $_ -Raw
        }
      }
      else
      {
        $VmImageId | ForEach-Object{
          $img += Get-RavelloImage -ImageId $_ -Raw
        }
      }
      if(!$sApp.Body.design.vms)
      {
        Add-Member -InputObject $sApp.Body.design -Name vms -Value $img -MemberType NoteProperty
      }
    }   
    If ($PSCmdlet.ShouldProcess("Changing application"))
    {
        Invoke-RavRest @sApp
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId')]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName')]
    [string]$ApplicationName
  )
  
  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($ApplicationName)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      $ApplicationId = $app.id
    }
    $sApp = @{
      Method  = 'Delete'
      Request = "applications/$($ApplicationId)"
    }
    If ($PSCmdlet.ShouldProcess("Removing application"))
    {
        Invoke-RavRest @sApp
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationPublishLocation
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [string]$PreferredCloud
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/findPublishLocations"
      Body    = @{
        id = $ApplicationId
      }
    }

    if($PreferredCloud)
    {
      $sApp.Body.Add('preferredCloud',$PreferredCloud)
    }
    If ($PSCmdlet.ShouldProcess("Find application publishing site"))
    {    
        Invoke-RavRest @sApp
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Publish-RavelloApplication
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [ValidateScript({
          (Get-RavelloApplication | Get-RavelloApplicationPublishLocation).cloudName -contains $_
    })]
    [string]$PreferredCloud,
    [ValidateScript({
          (Get-RavelloApplication | Get-RavelloApplicationPublishLocation).regionName -contains $_
    })]
    [string]$PreferredRegion,
    [ValidateSet('COST_OPTIMIZED','PERFORMANCE_OPTIMIZED')]
    [string]$OptimizationLevel,
    [Switch]$StartAllVM = $false
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/publish"
      Body    = @{
        id          = [string]$ApplicationId
        startAllVms = ([string]$StartAllVM).ToLower()
      }
    }
    if($PreferredCloud)
    {
      $sApp.Body.Add('preferredCloud',$PreferredCloud)
    }
    if($PreferredRegion)
    {
      $sApp.Body.Add('preferredRegion',$PreferredRegion)
    }
    if($OptimizationLevel)
    {
      $sApp.Body.Add('optimizationLevel',$OptimizationLevel)
    }
    If ($PSCmdlet.ShouldProcess("Publish application"))
    {
        Invoke-RavRest @sApp
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloApplicationVmVnc
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName',ValueFromPipelineByPropertyName)]
    [string]$ApplicationName,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId')]
    [long]$VmId
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sApp = @{
      Method = 'Get'
    }
    if($ApplicationName -and !$ApplicationId)
    {
      $app = Get-RavelloApplication -ApplicationName $ApplicationName
      if($app)
      {
        $ApplicationId = $app.id
      }
    }
    elseif($ApplicationId -ne 0)
    {
        $app = Get-RavelloApplication -ApplicationId $ApplicationId
    }
    if($VmId -ne 0)
    {
      Write-Verbose "`tParam VmId used - VM id: $($VmId)"
      $vm = Get-RavelloApplication -ApplicationId $app.id -VmId $VmId -Deployment
      if($vm.State -eq 'STARTED')
      {
          $sApp.Request = "applications/$($ApplicationId)/vms/$($VmId)/vncUrl"
          If ($PSCmdlet.ShouldProcess("Get VNC Url"))
          {
            Invoke-RavRest @sApp
          }
      }
    }
    elseif($app.deployment.vms -and $VmName)
    {
      $app.deployment.vms |
      Where-Object{$_.State -eq 'STARTED' -and $_.Name -eq $VmName} |
      ForEach-Object{
        Write-Verbose "`tVM id: $($_.id)"
        $sApp.Request = "applications/$($ApplicationId)/vms/$($_.id)/vncUrl"
        If ($PSCmdlet.ShouldProcess("Get VNC Url"))
        {
            Invoke-RavRest @sApp
        }
      }
    }
    elseif($app.deployment.vms)
    {
      $app.deployment.vms | 
      where-Object{$_.State -eq 'STARTED'} | %{
        Write-Verbose "`tVM id: $($_.id)"
        $sApp.Request = "applications/$($ApplicationId)/vms/$($_.id)/vncUrl"
        If ($PSCmdlet.ShouldProcess("Get VNC Url"))
        {
            New-Object -TypeName PsObject -Property @{
                VmName = $_.Name
                VncUrl = (Invoke-RavRest @sApp)
            }
        }
      }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Invoke-RavelloApplicationAction
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId',ValueFromPipelineByPropertyName = $true)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName',ValueFromPipelineByPropertyName = $true)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId',ValueFromPipelineByPropertyName = $true)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName',ValueFromPipelineByPropertyName = $true)]
    [string]$ApplicationName,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId')]
    [long]$VmId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName')]
    [string]$VmName,
    [ValidateSet('PublishUpdates','Start','Stop','Restart','Redeploy','Repair','ResetDisks','Shutdown','Poweroff')] 
    [String]$Action,
    [long]$ExpirationFromNowSeconds
  )

  process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"

    $sTime = @{}
    $PSBoundParameters.GetEnumerator() |
    Where-Object{
      $_.Key -notmatch '^Vm|^Action'
    } |
    ForEach-Object{
      $sTime.Add($_.Key,$_.Value)
    }
    Set-RavelloApplicationTimeout @sTime

    $Action = $Action.ToLower().Replace('resetdisks','resetDisks')
        
    $sApp = @{
      Method = 'Post'
      Body   = @{
        ids = @()
      }
    }
    if($ApplicationName -and !$ApplicationId)
    {
      $app = Get-RavelloApplication -Name $ApplicationName -Deployment
      if($app)
      {
        $ApplicationId = $app.id
      }
      else
      {
        Throw 'Application not found'
      }
    }
    if($VmId -ne 0)
    {
      Write-Verbose "`tParam VmId used - VM id: $($VmId)"
      $sApp.Request = "applications/$($ApplicationId)/vms/$($Action)"
      $sApp.Body.ids += $VmId
    }
    elseif($VmName -eq '' -and $VmId -eq 0)
    {
      Write-Verbose 'Action on all VMs'
      if( -notcaontains $Action)
      {
        Throw
      }
      if($Action -eq 'ResetDisks')
      {
        Throw 'ResetDisks action requires a VmName or a VmId'
      }
      $sApp.Body.Remove('ids')
      $sApp.Body.Add('id',$ApplicationId)
      $sApp.Request = "applications/$($ApplicationId)/$($Action)"
    }
    elseif($app.deployment.vms)
    {
      if($app.deployment.vms.name -contains $VmName)
      {
        $app.deployment.vms |
        Where-Object{
          $_.Name -eq $VmName
        } |
        ForEach-Object{
          Write-Verbose "`tVM id: $($_.id)"
          $sApp.Body.ids += $_.id
        }
        $sApp.Request = "applications/$($ApplicationId)/vms/$($Action)"
      }
      else
      {
        Throw 'VM not found in application'
      }
    }
    else
    {
      Throw 'No VMs found in application'
    }
    If ($PSCmdlet.ShouldProcess("Take action on VM"))
    {
        Invoke-RavRest @sApp
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloApplicationTimeout
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName',ValueFromPipelineByPropertyName)]
    [string]$Name,
    [long]$ExpirationFromNowSeconds = 7200
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    Write-Verbose "$($PSCmdlet.ParameterSetName)"
    if($Name -and !$ApplicationId)
    {
      $app = Get-RavelloApplication -Name $Name
      if($app)
      {
        $ApplicationId = $app.id
      }
    }
    $sApp = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/setExpiration"
      Body    = @{
        expirationFromNowSeconds = $ExpirationFromNowSeconds
      }
    }
    If ($PSCmdlet.ShouldProcess("Set Application VM timeout"))
    {
        ConvertFrom-JsonDateTime -DateTime (Invoke-RavRest @sApp)
    }
  }
}
#endregion Applications

#region Tasks
# .ExternalHelp Ravello-Help.xml
function Get-RavelloTask
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low',DefaultParameterSetName="Default")]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId',ValueFromPipelineByPropertyName = $true)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [long]$TaskId
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($ApplicationName)
    {
      $ApplicationId = Get-RavelloApplication -Name $ApplicationName | Select-Object -ExpandProperty id
    }
    $sTask = @{
      Method  = 'Get'
      Request = "applications/$($ApplicationId)/tasks"
    }
    if($TaskId)
    {
      $sTask.Request = $sTask.Request.Replace('tasks',"tasks/$($TaskId)")
    }
    If ($PSCmdlet.ShouldProcess("Retrieve tasks"))
    {
        $tasks = Invoke-RavRest @sTask
        $tasks | ForEach-Object{
          $_.ScheduleInfo.start = ConvertFrom-JsonDateTime -DateTime $_.ScheduleInfo.start
          if($_.scheduleInfo.end)
          {
            $_.ScheduleInfo.end = ConvertFrom-JsonDateTime -DateTime $_.ScheduleInfo.end
          }
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloTask
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId',ValueFromPipelineByPropertyName = $true)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $true)]
    [ValidateSet('Stop','Start','Blueprint')]
    [string]$Action,
    [string]$Description,
    [DateTime]$Start,
    [DateTime]$Finish,
    [string]$Cron
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($ApplicationName)
    {
      $ApplicationId = Get-RavelloApplication -Name $ApplicationName | Select-Object -ExpandProperty id
    }
    $sTask = @{
      Method  = 'Post'
      Request = "applications/$($ApplicationId)/tasks"
      Body    = @{
        action       = $Action.ToUpper()
        scheduleInfo = @{
          start          = ''
          end            = ''
          cronExpression = ''
        }
        description  = ''
      }
    }
    # seconds in cron expression need to be 0 (zero)
    if($Start)
    {
      $Start = $Start.ToUniversalTime().AddSeconds(-$Start.Second)
    }
    if($Finish)
    {
      $Finish = $Finish.ToUniversalTime()
    }
    $t = (Get-Date).AddMinutes(10).ToUniversalTime()

    # seconds in cron expression need to be 0 (zero)
    if(!$Cron)
    {
      $Cron = "0 $($t.Minute) $($t.Hour) $($t.Day) $($t.Month) ? $($t.Year)"
    }
    $sTask.Body.scheduleInfo.cronExpression = $Cron
    if($Start -and $Start -ge $t)
    {
      $sTask.Body.scheduleInfo.start = ConvertTo-JsonDateTime -Date $Start
    }
    elseif($Start -and $Start -lt $t)
    {
      $sTask.Body.scheduleInfo.start = ConvertTo-JsonDateTime -Date $t
    }
    if($Finish -and $Finish -ge $t)
    {
      $sTask.Body.scheduleInfo.end = ConvertTo-JsonDateTime -Date $Finish
    }
    elseif($Finish -and $Finish -lt $t)
    {
      $sTask.Body.scheduleInfo.end = ConvertTo-JsonDateTime -Date $t
    }
    if($Description -ne '')
    {
      $sTask.Body.description = $Description
    }
    If ($PSCmdlet.ShouldProcess("Start task"))
    {
        Invoke-RavRest @sTask
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloTask
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'TaskId',ValueFromPipelineByPropertyName = $true)]
    [Alias('id')]
    [long]$TaskId,
    [ValidateSet('Stop','Start','Blueprint')]
    [string]$Action,
    [string]$Description,
    [DateTime]$Start,
    [DateTime]$Finish,
    [string]$Cron
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"

    $task = Get-RavelloTask -TaskId $TaskId
    $sTask = @{
      Method  = 'Put'
      Request = "applications/$($task.entityId)/tasks/$($task.id)"
      Body    = @{
        action       = $task.action
        entityId     = $task.entityId
        entityType   = $task.entityType
        id           = $task.id
        scheduleInfo = @{
          start          = ''
          end            = ''
          cronExpression = ''
          args           = $task.scheduleInfo.args
        }
        description  = $task.description
      }
    }
    if($Start)
    {
      $Start = $Start.ToUniversalTime().AddSeconds(-$Start.Second)
    }
    elseif($task.scheduleInfo.start -ne $null)
    {
      $Start = (Get-Date -Second 0).ToUniversalTime()
    }
    if($Finish)
    {
      $Finish = $Finish.ToUniversalTime()
    }
    elseif($task.scheduleInfo.end -ne $null)
    {
      $Finish = $task.scheduleInfo.end.ToUniversalTime()
    }

    $t = (Get-Date -Second 0).AddMinutes(10).ToUniversalTime()

    $sTask.Body.scheduleInfo.cronExpression = "0 $($t.Minute) $($t.Hour) $($t.Day) $($t.Month) ? $($t.Year)"
    if($Action)
    {
      $sTask.Body.action = $Action
    }
    if($Start)
    {
      if($Start -and $Start -ge $t)
      {
        $sTask.Body.scheduleInfo.start = ConvertTo-JsonDateTime -Date $t
      }
      elseif($Start -and $Start -lt $t)
      {
        $sTask.Body.scheduleInfo.start = ConvertTo-JsonDateTime -Date $Start
      }
    }
    if($Finish)
    {
      if($Finish -and $Finish -ge $t)
      {
        $sTask.Body.scheduleInfo.end = ConvertTo-JsonDateTime -Date $Finish
      }
      elseif($Finish -and $Finish -lt $t)
      {
        $sTask.Body.scheduleInfo.end = ConvertTo-JsonDateTime -Date $t
      }
    }
    if($Description)
    {
      $sTask.Body.description = $Description
    }
    If ($PSCmdlet.ShouldProcess("Change task"))
    {
        Invoke-RavRest @sTask
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloTask
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId',ValueFromPipelineByPropertyName = $true)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName')]
    [string]$ApplicationName,
    [long]$TaskId
  )

  process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($ApplicationName)
    {
      $ApplicationId = Get-RavelloApplication -Name $ApplicationName | Select-Object -ExpandProperty id
    }
    $sTask = @{
      Method  = 'Delete'
      Request = "applications/$($ApplicationId)/tasks"
    }
    if($TaskId)
    {
      $sTask.Request = $sTask.Request.Replace('tasks',"tasks/$($TaskId)")
    }
    If ($PSCmdlet.ShouldProcess("Remove task"))
    {    
        Invoke-RavRest @sTask
    }
  }
}
#endregion

#region Blueprints
# .ExternalHelp Ravello-Help.xml
function Get-RavelloBlueprint
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low',DefaultParameterSetName="Default")]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'BlueprintId')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $true,ParameterSetName = 'BlueprintName')]
    [string]$BlueprintName,
    [Switch]$Private
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sBlue = @{
      Method  = 'Get'
      Request = 'blueprints'
    }
    if($BlueprintName)
    {
      $BlueprintId = Get-RavelloBlueprint |
      Where-Object{
        $_.name -eq $BlueprintName
      } |
      Select-Object -ExpandProperty id
    }
    if($BlueprintId)
    {
      $sBlue.Request = $sBlue.Request.Replace('blueprints',"blueprints/$($BlueprintId)")
    }
    if($Private)
    {
      $org = Get-RavelloOrganization
      $sBlue.Request = $sBlue.Request.Replace('blueprints',"organizations/$($org.id)/blueprints")
    }

    If ($PSCmdlet.ShouldProcess("Retrieve blueprints"))
    {
        $bp = Invoke-RavRest @sBlue
        $bp | ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloBlueprint
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'ApplicationId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'ApplicationName')]
    [string]$ApplicationName,
    [string]$Description = '',
    [switch]$Offline
  )

  Process
  {
    if($ApplicationName)
    {
      $ApplicationId = Get-RavelloApplication |
      Where-Object{
        $_.Name -eq $Name
      } |
      Select-Object -ExpandProperty id
    }
    if($ApplicationId)
    {
      $sBlue = @{
        Method  = 'Post'
        Request = 'blueprints'
        Body    = @{
          applicationId = $ApplicationId
          blueprintName = $Name
          offline       = ([string]$Offline).ToLower()
          description   = $Description
        }
      }
      If ($PSCmdlet.ShouldProcess("Create blueprint"))
      {
          $bp = Invoke-RavRest @sBlue
          $bp | ForEach-Object{
            $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
            $_
          }
      }
    }
    else
    {
      Throw 'New-RavelloBlueprint requires an Application (Name or Id)'
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloBlueprintPublishLocation
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'BlueprintId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $true,ParameterSetName = 'BlueprintName')]
    [string]$BlueprintName,
    [string]$PreferredCloud,
    [string]$PreferredRegion
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"

    if($BlueprintName)
    {
      $BlueprintId = Get-RavelloBlueprint |
      Where-Object{
        $_.name -eq $BlueprintName
      } |
      Select-Object -ExpandProperty id
    }
    $sBlue = @{
      Method  = 'Post'
      Request = "blueprints/$($BlueprintId)/findPublishLocations"
      Body    = @{
        id = $BlueprintId
      }
    }

    if($PreferredCloud)
    {
      $sBlue.Body.Add('preferredCloud',$PreferredCloud)
    }
    if($PreferredRegion)
    {
      $sBlue.Body.Add('preferredRegionCloud',$PreferredRegion)
    }
    If ($PSCmdlet.ShouldProcess("Get blueprint publication location"))
    {
        Invoke-RavRest @sBlue
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloBlueprint
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'BlueprintId')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $true,ParameterSetName = 'BlueprintName')]
    [string]$BlueprintName
  )

  process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($BlueprintName)
    {
      $BlueprintId = Get-RavelloBlueprint |
      Where-Object{
        $_.name -eq $BlueprintName
      } |
      Select-Object -ExpandProperty id
    }
    if($BlueprintId)
    {
      $sBlue = @{
        Method  = 'Delete'
        Request = "blueprints/$($BlueprintId)"
      }
      If ($PSCmdlet.ShouldProcess("Remove blueprint"))
      {
          Invoke-RavRest @sBlue
      }
    }
  }
}
#endregion

#region Images
# .ExternalHelp Ravello-Help.xml
function Get-RavelloImage
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low',DefaultParameterSetName="Default")]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'ImageId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $true,ParameterSetName = 'ImageName')]
    [string]$ImageName,
    [switch]$Private,
    [Parameter(DontShow)]
    [switch]$Raw
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sImage = @{
      Method  = 'Get'
      Request = 'images'
    }

    if($ImageName)
    {
      $ImageId = Get-RavelloImage |
      Where-Object{
        $_.Name -eq $ImageName
      } |
      Select-Object -ExpandProperty id
    }
    if($ImageId)
    {
      $sImage.Request = $sImage.Request.Replace('images',"images/$($ImageId)")
    }
    if($Private)
    {
      $org = Get-RavelloOrganization
      $sImage.Request = $sImage.Request.Replace('images',"organizations/$($org.id)/images")
    }
    If ($PSCmdlet.ShouldProcess("Get image"))
    {
        $image = Invoke-RavRest @sImage
        $image | ForEach-Object{
          if(!$Raw)
          {
            $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          }
          $_
        }
     }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloImage
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [string]$Name,
    [Parameter(Mandatory = $true,ParameterSetName = 'Id',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$AppBpId,
    [Parameter(Mandatory = $true,ParameterSetName = 'ApplicationName')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $true,ParameterSetName = 'BlueprintName')]
    [string]$BlueprintName,
    [long]$VmId,
    [string]$VmName,
    [string]$NewImageName,
    [switch]$Offline = $false
  )
    
  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($AppBpId)
    {
      if(Get-RavelloApplication -ApplicationId $Id -ErrorAction SilentlyContinue)
      {
        $blueprint = $false
        $ApplicationId = $AppBpId
      }
      else
      {
        $blueprint = $true
        $BlueprintId = $AppBpId
      }
    }

    if($BlueprintId -or $BlueprintName)
    {
      if($BlueprintName)
      {
        $bp = Get-RavelloBlueprint -Name $BlueprintName
        $Id = $bp.id
      }
      if($VmName)
      {
        $VmId = $bp.design.vms |
        Where-Object{
          $_.Name -eq $VmName
        } |
        Select-Object -ExpandProperty id
      }
    }
    else
    {
      if($ApplicationName)
      {
        $app = Get-RavelloApplication -Name $ApplicationName | Select-Object -ExpandProperty id
      }
      if($VmName)
      {
        $VmId = Get-RavelloVM -ApplicationId $Id -VmName $VmName | Select-Object -ExpandProperty id
      }
    }
    $sImage = @{
      Method  = 'Post'
      Request = 'images'
      Body    = @{
        applicationId = $Id
        vmId          = $VmId
        offline       = ($Offline.ToString()).ToLower()
        blueprint     = $blueprint
        imageName     = $NewImageName
      }
    }
    If ($PSCmdlet.ShouldProcess("Create image"))
    {
        $image = Invoke-RavRest @sImage
        $image | ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_    
        }
    }
  }    
}

# .ExternalHelp Ravello-Help.xml
function Update-RavelloImage
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'ImageId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $true,ParameterSetName = 'ImageName')]
    [string]$ImageName,
    [string]$Description,
    [Parameter(Mandatory = $true,ParameterSetName = 'ImageObj')]
    [psobject]$Image
        
  )
    
  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($Image)
    {
      $img = $Image
    }
    elseif($ImageName)
    {
      $img = Get-RavelloImage -Name $ImageName
    }
    else
    {
      $img = Get-RavelloImage -ImageId $ImageId
    }
    $sImage = @{
      Method  = 'Put'
      Request = "images/$($image.id)"
      Body    = $img
    }
    $sImage.Body.creationTime = ConvertTo-JsonDateTime -Date $sImage.Body.creationTime

    if($Description)
    {
      $sImage.Body.description = $Description
    }
    If ($PSCmdlet.ShouldProcess("Change image"))
    {
        Invoke-RavRest @sImage
    }
  }    
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloImage
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'ImageId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ImageId,
    [Parameter(Mandatory = $true,ParameterSetName = 'ImageName')]
    [string]$ImageName
  )

  process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($ImageName)
    {
      $ImageId = Get-RavelloImage -Name $ImageName | Select-Object -ExpandProperty id
    }

    $sImage = @{
      Method  = 'Delete'
      Request = "images/$($ImageId)"
    }
    If ($PSCmdlet.ShouldProcess("Remove image"))
    {  
        Invoke-RavRest @sImage
    }
  }
}
#endregion

#region Diskimages
# .ExternalHelp Ravello-Help.xml
function Get-RavelloDiskImage
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low',DefaultParameterSetName="Default")]
  param(
    [Parameter(ParameterSetName = 'DiskImageId')]
    [long]$DiskImageId,
    [Parameter(ParameterSetName = 'DiskImageName')]
    [string]$DiskImageName
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($DiskImageName)
    {
      $images = Get-RavelloDiskImage
      $DiskImageId = $images |
      Where-Object{
        $_.name -eq $DiskImageName
      } |
      Select-Object -ExpandProperty id
    }
    $sDiskImage = @{
      Method  = 'Get'
      Request = 'diskImages'
    }

    if($DiskImageId)
    {
      $sDiskImage.Request = $sDiskImage.Request.Replace('diskImages',"diskImages/$($DiskImageId)")
    }
    If ($PSCmdlet.ShouldProcess("Get disk images"))
    {
        $disk = Invoke-RavRest @sDiskImage
        $disk  | ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloDiskImage
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-DiskId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-DiskName',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName-DiskId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName-DiskName',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-DiskId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-DiskName',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-DiskId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-DiskName',ValueFromPipelineByPropertyName)]
    [string]$ApplicationName,
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmId-DiskId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmId-DiskName',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmName-DiskId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmName-DiskName',ValueFromPipelineByPropertyName)]
    [long]$BlueprintId,
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmId-DiskId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmId-DiskName',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmName-DiskId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmName-DiskName',ValueFromPipelineByPropertyName)]
    [string]$BlueprintName,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmId-DiskName')]
    [long]$VmId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmNamed-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmId-DiskName')]
    [string]$VmName,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmName-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmId-DiskId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmName-DiskId')]
    [long]$DiskId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId-VmName-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmId-DiskName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName-VmName-DiskName')]
    [string]$DiskName,
    [string]$NewDiskName,
    [string]$Description,
    [switch]$Offline = $false
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if(!$Id)
    {
      if($ApplicationName)
      {
        $obj = Get-RavelloApplication -Name $ApplicationName
        $blueprint = $false
      }
      elseif($BlueprintName)
      {
        $obj = Get-RavelloBlueprint -Name $BlueprintName
        $blueprint = $true
      }
      $Id = $obj.id
      if($VmName)
      {
        $objVm = $obj.design.vms | Where-Object{
          $_.name -eq $VmName
        }
        $VmId = $objVm.id
      }
      if($DiskName)
      {
        $objDisk = $objVm.hardDrives | Where-Object{
          $_.name -eq $DiskName
        }
        $DiskId = $objDisk.id
      }
    }

    $sDiskImage = @{
      Method  = 'Post'
      Request = 'diskImages'
      Body    = @{
        applicationId = $Id
        vmId          = $VmId
        diskId        = $DiskId
        diskImage     = @{
          name = $Name
        }
        offline       = ($Offline.ToString()).ToLower()
        blueprint     = $blueprint
      }
    }
    If ($PSCmdlet.ShouldProcess("Create disk image"))
    {
        $disk = Invoke-RavRest @sDiskImage
        $disk  | ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloDiskImage
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'DiskImageId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskImageId,
    [Parameter(Mandatory = $true,ParameterSetName = 'DiskImageName')]
    [string]$DiskImageName,
    [string]$NewName,
    [string]$Description,
    [ValidateSet('GB','MB','KB','BYTE')]
    [string]$SizeUnit,
    [long]$Size
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($DiskImageName)
    {
      $disk = Get-RavelloDiskImage -DiskImageName $DiskImageName
    }
    else
    {
      $disk = Get-RavelloDiskImage -DiskImageId $DiskImageId
    }
    if(!$NewName)
    {
      $NewName = $disk.name
    }
    if(!$SizeUnit)
    {
      $SizeUnit = $disk.size.unit
    }
    if(!$Size)
    {
      $Size = $disk.size.value
    }
    $sDiskImage = @{
      Method  = 'Put'
      Request = "diskImages/$($disk.id)"
      Body    = @{
        id   = $disk.id
        name = $NewName
        size = @{
          unit  = $SizeUnit
          value = $Size
        }
      }
    }
    if($Description)
    {
      $sDiskImage.Body.Add('description',$Description)
    }
    If ($PSCmdlet.ShouldProcess("Change disk image"))
    {
        $newdisk = Invoke-RavRest @sDiskImage
        $newdisk  | ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloDiskImage
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'DiskImageId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskImageId,
    [Parameter(Mandatory = $true,ParameterSetName = 'DiskImageName')]
    [string]$DiskImageName
  )

  process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($DiskImageName)
    {
      $DiskImageId = Get-RavelloDiskImage -DiskImageName $DiskImageName | Select-Object -ExpandProperty id
    }
    $sDiskImage = @{
      Method  = 'Delete'
      Request = "diskImages/$($DiskImageId)"
    }
    If ($PSCmdlet.ShouldProcess("Remove disk image"))
    {
        Invoke-RavRest @sDiskImage
    }
  }
}
#endregion

#region Key Pairs
# .ExternalHelp Ravello-Help.xml
function Get-RavelloKeyPair
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low',DefaultParameterSetName="Default")]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'KeyPairId')]
    [long]$KeyPairId,
    [Parameter(Mandatory = $true,ParameterSetName = 'KeyPairName')]
    [string]$KeyPairName
  )
    
  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sKeyPair = @{
      Method  = 'Get'
      Request = 'keypairs'
    }
    if($KeyPairName)
    {
      $KeyPairId = Get-RavelloKeyPair |
      Where-Object{
        $_.Name -eq $KeyPairName
      } |
      Select-Object -ExpandProperty id
    }
    if($KeyPairId)
    {
      $sKeyPair.Request = $sKeyPair.Request.Replace('keypairs',"keypairs/$($KeyPairId)")
    }
    If ($PSCmdlet.ShouldProcess("Get key pairs"))
    {
        $keypairs = Invoke-RavRest @sKeyPair
        $keypairs | ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_.creator.invitationTime = ConvertFrom-JsonDateTime -DateTime $_.creator.invitationTime
          $_.creator.activateTime = ConvertFrom-JsonDateTime -DateTime $_.creator.activateTime
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloKeyPair
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'New')]
    [string]$Name,
    [Parameter(Mandatory = $true,ParameterSetName = 'New',ValueFromPipelineByPropertyName)]
    [string]$PublicKey,
    [Parameter(Mandatory = $true,ParameterSetName = 'Generate')]
    [switch]$Generate
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sKeyPair = @{
      Method  = 'Post'
      Request = 'keypairs'
    }

    if($Generate)
    {
      $sKeyPair.Request = 'keypairs/generate'
    }
    else
    {
      $sKeyPair.Add('Body',@{
          'name'    = $Name
          'publicKey' = $PublicKey
      })
    }
    If ($PSCmdlet.ShouldProcess("Create key pair"))
    {
        $keypair = Invoke-RavRest @sKeyPair
        $keypair | ForEach-Object{
          if($_.creationTime)
          {
            $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          }
          if($_.creator.invitationTime)
          {
            $_.creator.invitationTime = ConvertFrom-JsonDateTime -DateTime $_.creator.invitationTime
          }
          if($_.creator.activateTime)
          {
            $_.creator.activateTime = ConvertFrom-JsonDateTime -DateTime $_.creator.activateTime
          }
          $_
        }
    }
  }    
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloKeyPair
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'KeyPairId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$KeyPairId,
    [Parameter(Mandatory = $true,ParameterSetName = 'KeyPairName')]
    [long]$KeyPairName,
    [string]$NewName
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($KeyPairName)
    {
      $KeyPairId = Get-RavelloKeyPair |
      Where-Object{
        $_.Name -eq $KeyPairName
      } |
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
    If ($PSCmdlet.ShouldProcess("Change key pair"))
    {
        $keypair = Invoke-RavRest @sKeyPair
        $keypair | ForEach-Object{
          if($_.creationTime)
          {
            $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          }
          if($_.creator.invitationTime)
          {
            $_.creator.invitationTime = ConvertFrom-JsonDateTime -DateTime $_.creator.invitationTime
          }
          if($_.creator.activateTime)
          {
            $_.creator.activateTime = ConvertFrom-JsonDateTime -DateTime $_.creator.activateTime
          }
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloKeyPair
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'KeyPairId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$KeyPairId,
    [Parameter(Mandatory = $true,ParameterSetName = 'KeyPairName')]
    [string]$KeyPairName
  )

  process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($KeyPairName)
    {
      $KeyPairId = Get-RavelloKeyPair |
      Where-Object{
        $_.Name -eq $KeyPairName
      } |
      Select-Object -ExpandProperty id
    }
    $sKeyPair = @{
      Method  = 'Delete'
      Request = "keypairs/$($KeyPairId)"
    }
    If ($PSCmdlet.ShouldProcess("Remove key pair"))
    {
        Invoke-RavRest @sKeyPair
    }
  }
}
#endregion

#region Elastic IPs
# .ExternalHelp Ravello-Help.xml
function Get-RavelloElasticIP
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param()
    
  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sElasticIP = @{
      Method  = 'Get'
      Request = 'elasticIps'
    }
    If ($PSCmdlet.ShouldProcess("Get Elastic IPs"))
    {
        $eIP = Invoke-RavRest @sElasticIP
        $eIP | ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloElasticIP
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param()
    
  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sElasticIP = @{
      Method  = 'Post'
      Request = 'elasticIps'
    }
    If ($PSCmdlet.ShouldProcess("Create elastic IP"))
    {
        $eIP = Invoke-RavRest @sElasticIP
        $eIP | ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloElasticIP
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName)]
    [Alias('ip')]
    [string]$ElasticIpAddress
  )
    
  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sElasticIP = @{
      Method  = 'Delete'
      Request = "elasticIps/$($ElasticIpAddress)"
    }
    If ($PSCmdlet.ShouldProcess("Remove elastic IP"))
    {
        Invoke-RavRest @sElasticIP
    }
  }
}
#endregion

#region Organizations
# .ExternalHelp Ravello-Help.xml
function Get-RavelloOrganization
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low',DefaultParameterSetName="Default")]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'OrganizationId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$OrganizationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'OrganizationName')]
    [string]$OrganizationName,
    [Parameter(ParameterSetName = 'OrganizationName')]
    [Parameter(ParameterSetName = 'OrganizationId')]
    [switch]$Users = $false
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sOrg = @{
      Method  = 'Get'
      Request = 'organization'
    }
    if($OrganizationName)
    {
      $OrganizationId = Get-RavelloOrganization |
      Where-Object{
        $_.organizationName -eq $OrganizationName
      } |
      Select-Object -ExpandProperty id
    }
    if($OrganizationId)
    {
      if($Users)
      {
        $sOrg.Request = $sOrg.Request.Replace('organization',"organizations/$([String]$OrganizationId)/users")
      }
      else
      {
        $sOrg.Request = $sOrg.Request.Replace('organization',"organizations/$([String]$OrganizationId)")
      }
    }
    If ($PSCmdlet.ShouldProcess("Get Organization"))
    {
        Invoke-RavRest @sOrg
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloOrganization
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'OrganizationId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$OrganizationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'OrganizationName')]
    [string]$OrganizationName,
    [Parameter(Mandatory = $true)]
    [string]$NewOrganizationName
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($OrganizationName)
    {
      $OrganizationId = Get-RavelloOrganization |
      Where-Object{
        $_.name -eq $OrganizationName
      } |
      Select-Object -ExpandProperty id
    }
    $sOrganization = @{
      Method  = 'Put'
      Request = "organizations/$([String]$OrganizationId)"
      Body    = @{
        'organizationName' = $NewOrganizationName
      }
    }
    If ($PSCmdlet.ShouldProcess("Change organization"))
    {
        Invoke-RavRest @sOrganization
    }
  }
}
#endregion

#region Users
# .ExternalHelp Ravello-Help.xml
function Get-RavelloUser
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low',DefaultParameterSetName="Default")]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'UserName')]
    [string]$UserName,
    [Parameter(Mandatory = $true,ParameterSetName = 'UserId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$UserId,
    [Parameter(Mandatory = $true,ParameterSetName = 'AllUsers')]
    [switch]$All = $false
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sUser = @{
      Method = 'Get'
    }
    if($UserName -or $UserId)
    {
      $All = $true
    }
    if($All)
    {
      $sUser.Add('Request','users')
    }
    else
    {
      $sUser.Add('Request','user')
    }
    If ($PSCmdlet.ShouldProcess("Get users"))
    {
        $Users = Invoke-RavRest @sUser
        if($UserId)
        {
          $Users = $Users | Where-Object{
            $_.id -eq $UserId
          }
        }
        if($UserName)
        {
          $Users = $Users | Where-Object{
            "$($_.name) $($_.surname)" -eq $UserName
          }
        }
        $Users  | ForEach-Object{
          $_.invitationTime = ConvertFrom-JsonDateTime -DateTime $_.invitationTime
          if($_.activateTime)
          {
            $_.activateTime = ConvertFrom-JsonDateTime -DateTime $_.activateTime
          }
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloUser
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'OrganizationId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$OrganizationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'OrganizationName')]
    [string]$OrganizationName,
    [Parameter(Mandatory = $true)]
    [string]$EmailAddress,
    [Parameter(Mandatory = $true)]
    [string]$LastName,
    [Parameter(Mandatory = $true)]
    [string]$FirstName
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($OrganizationName)
    {
      $OrganizationId = Get-RavelloOrganization |
      Where-Object{
        $_.organizationName -eq $OrganizationName
      } |
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
    If ($PSCmdlet.ShouldProcess("Create user"))
    {
        $Users = Invoke-RavRest @sUser
        $Users  | ForEach-Object{
          $_.invitationTime = ConvertFrom-JsonDateTime -DateTime $_.invitationTime
          if($_.activateTime)
          {
            $_.activateTime = ConvertFrom-JsonDateTime -DateTime $_.activateTime
          }
          $_
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloUser
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'UserId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$UserId,
    [Parameter(Mandatory = $true)]
    [string]$EmailAddress,
    [Parameter(Mandatory = $true,ParameterSetName = 'UserName')]
    [string]$LastName,
    [Parameter(Mandatory = $true,ParameterSetName = 'UserName')]
    [string]$FirstName,
    [string[]]$Roles
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($LastName -and $FirstName)
    {
      $User = Get-RavelloUser -All | Where-Object{
        $_.name -eq $FirstName -and $_.surname -eq $LastName -and $_.email -eq $EmailAddress
      }
      $UserId = $User.id
    }
    else
    {
      $User = Get-RavelloUser | Where-Object{
        $_.id -eq $UserId
      }
    }
    $sUser = @{
      Method  = 'Put'
      Request = "users/$($UserId)"
      Body    = @{
        email   = $User.email
        surname = $LastName
        name    = $FirstName
        roles   = $Roles
      }
    }
    If ($PSCmdlet.ShouldProcess("Change user"))
    {
        $User = Invoke-RavRest @sUser
        $User  | ForEach-Object{
          $_.invitationTime = ConvertFrom-JsonDateTime -DateTime $_.invitationTime
          if($_.activateTime)
          {
            $_.activateTime = ConvertFrom-JsonDateTime -DateTime $_.activateTime
          }
          $_
        }
    }
  }
}

# Not present in current version !
# .ExternalHelp Ravello-Help.xml
function Remove-RavelloUser
{

}
#endregion

#region Permissions
# .ExternalHelp Ravello-Help.xml
function Get-RavelloPermissionsGroup
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low',DefaultParameterSetName="Default")]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'PermissionGroupId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$PermissionGroupId,
    [Parameter(Mandatory = $true,ParameterSetName = 'PermissionGroupName')]
    [string]$PermissionGroupName,
    [Parameter(ParameterSetName = 'PermissionGroupId')]
    [Parameter(ParameterSetName = 'PermissionGroupName')]
    [switch]$Users,
    [Parameter(Mandatory = $true,ParameterSetName = 'UserId')]
    [long]$UserId,
    [Parameter(Mandatory = $true,ParameterSetName = 'UserName')]
    [string]$UserName
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sPGroup = @{
      Method  = 'Get'
      Request = 'permissionsGroups'
    }
    if($PermissionGroupName)
    {
      $pg = Get-RavelloPermissionsGroup | Where-Object{
        $_.name -eq $PermissionGroupName
      }
      $PermissionGroupId = $pg.id
    }
    if($PermissionGroupId)
    {
      $sPGroup.Request = $sPGroup.Request.Replace('permissionsGroups',"permissionsGroups/$([String]$PermissionGroupId)")
    }
    if($Users)
    {
      $sPGroup.Request = $sPGroup.Request, 'users' -join '/'
    }
    if($UserName)
    {
      $UserId = Get-RavelloUser -UserName $UserName | Select-Object -ExpandProperty id
    }
    if($UserId)
    {
      $sPGroup.Request = $sPGroup.Request.Replace('permissionsGroups',"permissionsGroups?userId=$([String]$UserId)")
    }
    If ($PSCmdlet.ShouldProcess("Get permissions group"))
    {
        $groups = Invoke-RavRest @sPGroup
        $groups | ForEach-Object{
          if($_.creationTime)
          {
            $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          }
          $_    
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function New-RavelloPermissionsGroup
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [string]$Description,
    [PSObject[]]$Permissions
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sPGroup = @{
      Method  = 'Post'
      Request = 'permissionsGroups'
      Body    = @{
        name        = $Name
        description = $Description
        permissions = $Permissions
      }
    }
    If ($PSCmdlet.ShouldProcess("Create permissions group"))
    {
        $pg = Invoke-RavRest @sPGroup
        $pg | ForEach-Object{
          if($_.creationTime)
          {
            $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          }
          $_    
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloPermissionsGroup
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'PermissionGroupId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$PermissionGroupId,
    [Parameter(Mandatory = $true,ParameterSetName = 'PermissionGroupName')]
    [string]$PermissionGroupName,
    [string]$Name,
    [string]$Description,
    [PSObject[]]$Permissions
  )

  Process
  {
    if($PermissionGroupName)
    {
      $pg = Get-RavelloPermissionsGroup -PermissionGroupName $PermissionGroupName
      $PermissionGroupId = $pg.id
    }
    else
    {
      $pg = Get-RavelloPermissionsGroup -PermissionGroupId $PermissionGroupId
    }
    $sPGroup = @{
      Method  = 'Put'
      Request = "permissionsGroups/$($PermissionGroupId)"
      Body    = $pg
    }
    if($Name)
    {
      $sPGroup.Body.name = $Name
    }
    if($Description)
    {
      $sPGroup.Body.description = $Description
    }
    if($Permissions)
    {
      $sPGroup.Body.permissions = $Permissions
    }
    $sPGroup.Body.creationTime = ConvertTo-JsonDateTime -Date $sPGroup.Body.creationTime 
    If ($PSCmdlet.ShouldProcess("Change permissions group"))
    {
        $pg = Invoke-RavRest @sPGroup
        $pg | ForEach-Object{
          if($_.creationTime)
          {
            $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          }
          $_    
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Add-RavelloPermissionsGroupUser
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'PGId-UName',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'PGId-UId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$PermissionGroupId,
    [Parameter(Mandatory = $true,ParameterSetName = 'PGName-UName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'PGName-UId')]
    [string]$PermissionGroupName,
    [Parameter(Mandatory = $true,ParameterSetName = 'PGId-UId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'PGName-UId')]
    [long]$UserId,
    [Parameter(Mandatory = $true,ParameterSetName = 'PGId-UName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'PGName-UName')]
    [string]$UserName
  )

  Process
  {
    if($PermissionGroupName)
    {
      $pg = Get-RavelloPermissionsGroup -PermissionGroupName $PermissionGroupName
      $PermissionGroupId = $pg.id
    }
    else
    {
      $pg = Get-RavelloPermissionsGroup -PermissionGroupId $PermissionGroupId
    }
    if($UserName)
    {
      $User = Get-RavelloUser -UserName $UserName
      $UserId = $User.id
    }
    $sPGroup = @{
      Method  = 'Post'
      Request = "permissionsGroups/$($PermissionGroupId)/users"
      Body    = @{
        userId = $UserId
      }
    }
    If ($PSCmdlet.ShouldProcess("Add user to permissions group"))
    {
        $pg = Invoke-RavRest @sPGroup
        $pg | ForEach-Object{
          if($_.creationTime)
          {
            $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          }
          $_    
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloPermissionsGroup
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'PgId-UId',ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory = $true,ParameterSetName = 'PgId-UName',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$PermissionGroupId,
    [Parameter(Mandatory = $true,ParameterSetName = 'PgName-UId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'PgName-UName')]
    [string]$PermissionGroupName,
    [Parameter(Mandatory = $true,ParameterSetName = 'PgId-UId')]
    [Parameter(Mandatory = $true,ParameterSetName = 'PgName-UId')]
    [long]$UserId,
    [Parameter(Mandatory = $true,ParameterSetName = 'PgId-UName')]
    [Parameter(Mandatory = $true,ParameterSetName = 'PgName-UName')]
    [string]$UserName
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($PermissionGroupName)
    {
      $pg = Get-RavelloPermissionsGroup | Where-Object{
        $_.name -eq $PermissionGroupName
      }
      $PermissionGroupId = $pg.id
    }
    $sPGroup = @{
      Method  = 'Delete'
      Request = "permissionsGroups/$($PermissionGroupId)"
    }
    if($UserName -or $UserId)
    {
      if($UserName)
      {
        $User = Get-RavelloUser -UserName $UserName
        $UserId = $User.id
      }
      $sPGroup.Request = $sPGroup.Request, 'users', "$($UserId)" -join '/'
    }
    If ($PSCmdlet.ShouldProcess("Remove permissions group"))
    {
        $groups = Invoke-RavRest @sPGroup
        $groups | ForEach-Object{
          if($_.creationTime)
          {
            $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          }
          $_    
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloPermissionDescriptor
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param()

  Process
  {
    $sPGroup = @{
      Method  = 'Get'
      Request = 'permissionsGroups/describe'
    }
    If ($PSCmdlet.ShouldProcess("Get permission descriptors"))
    {
        $descriptors = Invoke-RavRest @sPGroup
        $descriptors
    }
  }
}
#endregion

#region Notifications
# .ExternalHelp Ravello-Help.xml
function Get-RavelloNotification
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [long]$ApplicationId,
    [string]$NotificationLevel,
    [long]$MaxResults,
    [DateTime]$Start,
    [DateTime]$Finish
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sNotification = @{
      Method  = 'Post'
      Request = 'notifications/search'
      Body    = @{}
    }

    if($ApplicationId)
    {
      $sNotification.Body.Add('appId',$ApplicationId)
    }
    if($NotificationLevel)
    {
      $sNotification.Body.Add('notificationLevel',$NotificationLevel)
    }
    if($MaxResults)
    {
      $sNotification.Body.Add('maxResults',$MaxResults)
    }
    if($Start)
    {
      If(!$Finish)
      {
        $Finish = Get-Date
      }
      $dtObj = @{
        'startTime' = [int64]($Start -(Get-Date '1/1/1970')).TotalMilliseconds
        'endTime' = [int64]($Finish -(Get-Date '1/1/1970')).TotalMilliseconds
      }
      $sNotification.Body.Add('dateRange',$dtObj)
    }
    If ($PSCmdlet.ShouldProcess("Get notifications"))
    {
        $notifications = Invoke-RavRest @sNotification
    
        $notifications.dateRange.startTime = ConvertFrom-JsonDateTime -DateTime $notifications.dateRange.startTime
        $notifications.dateRange.endTime = ConvertFrom-JsonDateTime -DateTime $notifications.dateRange.endTime
        $notifications.notification = $notifications.notification | ForEach-Object{
          $_.eventTimeStamp = ConvertFrom-JsonDateTime -DateTime $_.eventTimeStamp
          $_
        }
        $notifications
    }
  }
}
#endregion

#region User Alerts
# .ExternalHelp Ravello-Help.xml
function Get-RavelloUserAlert
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param()

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sUAlert = @{
      Method  = 'Get'
      Request = 'userAlerts'
    }

    If ($PSCmdlet.ShouldProcess("Get user alerts"))
    {
        Invoke-RavRest @sUAlert
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloUserAlert
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory = $true)]
    [string]$EventName,
    [Parameter(ParameterSetName = 'UserId')]
    [long]$UserId,
    [Parameter(ParameterSetName = 'UserName')]
    [string]$UserName
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    if($UserName)
    {
      $User = Get-RavelloUser -UserName $UserName
      $UserId = $User.id
    }
    $sUAlert = @{
      Method  = 'Post'
      Request = 'userAlerts'
      Body    = @{
        'eventName' = $EventName
      }
    }
    if($UserId)
    {
      $sUAlert.Body.Add('userId',$UserId)
    }
    If ($PSCmdlet.ShouldProcess("Change user alerts"))
    {
        Invoke-RavRest @sUAlert
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Remove-RavelloUserAlert
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'UserId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$EventId
  )

  Process
  {
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sUAlert = @{
      Method  = 'Delete'
      Request = "userAlerts/$($EventId)"
    }
    If ($PSCmdlet.ShouldProcess("Remove user alert"))
    {
        Invoke-RavRest @sUAlert
    }
  }
}
#endregion

#region Events
# .ExternalHelp Ravello-Help.xml
function Get-RavelloEvent
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param()

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sEvent = @{
      Method  = 'Get'
      Request = 'events'
    }
    If ($PSCmdlet.ShouldProcess("Get events"))
    {
        Invoke-RavRest @sEvent
    }
  }
}
#endregion

#region Billing
# .ExternalHelp Ravello-Help.xml
function Get-RavelloBilling
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [string]$Year = [string](Get-Date).AddMonths(-1).Year ,
    [string]$Month = '{0:D2}' -f ((Get-Date).AddMonths(-1).Month)
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sBill = @{
      Method  = 'Get'
      Request = 'billing'
    }
    if($Year -and $Month)
    {
      $sBill.Request = $sBill.Request.Replace('billing',"billing?year=$($Year)&month=$($Month)")
    }
    If ($PSCmdlet.ShouldProcess("Get billing"))
    {
        Invoke-RavRest @sBill
    }
  }
}
#endregion

#region VMs
# .ExternalHelp Ravello-Help.xml
function Get-RavelloVM
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'AppName')]
    [Parameter(ParameterSetName = 'VmName')]
    [Parameter(ParameterSetName = 'VmId')]
    [string]$ApplicationName,
    [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId')]
    [Parameter(ParameterSetName = 'VmName')]
    [Parameter(ParameterSetName = 'VmId')]
    [Alias('id')]
    [long]$ApplicationId,
    [Parameter(Mandatory = $true,ParameterSetName = 'VmName')]
    [string]$VmName,
    [Parameter(Mandatory = $true,ParameterSetName = 'VmId')]
    [long]$VmId
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    $sVM = @{
      Method  = 'Get'
      Request = 'applications/vms'
    }
    if($ApplicationName)
    {
      $ApplicationId = Get-RavelloApplication -ApplicationName $ApplicationName | Select-Object -ExpandProperty id
    }
    if($ApplicationId)
    {
      $sVM.Request = $sVM.Request.Replace('applications',"applications/$([String]$ApplicationId)")
    }
    if($VmName)
    {
      $VmId = Get-RavelloApplication -ApplicationId $ApplicationId -VmName $VmName | Select-Object -ExpandProperty id
    }
    if($VmId)
    {
      $sVM.Request = $sVM.Request.Replace('vms',"vms/$([String]$VmId)")
    }
    if($Deployment)
    {
      $sVM.Request = $sVM.Request, 'deployment' -join ';'
    }
    if($Properties)
    {
      $sVM.Request = $sVM.Request, 'properties' -join ';'
    }
    If ($PSCmdlet.ShouldProcess("Get VM"))
    {
        Invoke-RavRest @sVM
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Invoke-RavelloVMAction
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
  param(
    [PSObject]$VM,
    [ValidateSet('stop','start','shutdown','poweroff','restart','redeploy','repair','resetDisk')]
    [string]$Action
  )

  Process{
    Write-Verbose "$($MyInvocation.MyCommand.Name)"
    Write-Debug "VM     = $($VM.Name)"
    Write-Debug "Action = $($Action)"

    $sVM = @{
      Method  = 'Post'
      Request = "applications/$($VM.ApplicationId)/vms/$($VM.Id)/$($Action)"
    }
    If ($PSCmdlet.ShouldProcess("Perform action on VM"))
    {
        Invoke-RavRest @sVM
    }
  }
}
#endregion

#region Communities
# .ExternalHelp Ravello-Help.xml
function Get-RavelloRepo
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
  [string]$CommunityName
  )

  Process
  {
    $sRepo = @{
      Method  = 'Get'
      Request = 'communities'
    }
    If ($PSCmdlet.ShouldProcess("Get the Ravello repo"))
    {
        $comm = Invoke-RavRest @sRepo
        if($CommunityName)
        {
            $comm | where{$CommunityName -like $CommunityName}
        }
        else
        {$comm}
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloRepoBlueprint
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'ComId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$CommunityId,
    [Parameter(Mandatory = $true,ParameterSetName = 'ComName')]
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
    if($CommunityName)
    {
      $communities = Get-RavelloRepo
      $CommunityId = $communities |
      Where-Object{
        $_.name -eq $CommunityName
      } |
      Select-Object -ExpandProperty id
    }
    $sRepo = @{
      Method  = 'Get'
      Request = "communities/$($CommunityId)/blueprints"
    }
    if($BlueprintId -eq 0 -and !$BlueprintName)
    {$mask = '*'}
    elseif($BlueprintName)
    {$mask = $BlueprintName}
    else
    {$mask = "^$"}
    If ($PSCmdlet.ShouldProcess("Get blueprint from Ravello Repo"))
    {
        $bp = Invoke-RavRest @sRepo    
        $bp | where{$_.id -eq $BlueprintId -or $_.Name -like $mask} |
        ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_    
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloRepoDisk
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'ComId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$CommunityId,
    [Parameter(Mandatory = $true,ParameterSetName = 'ComName')]
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
    if($CommunityName)
    {
      $communities = Get-RavelloRepo
      $CommunityId = $communities |
      Where-Object{
        $_.name -eq $CommunityName
      } |
      Select-Object -ExpandProperty id
    }
    $sRepo = @{
      Method  = 'Get'
      Request = "communities/$($CommunityId)/diskImages"
    }
    if($DiskId -eq 0 -and !$DiskName)
    {$mask = '*'}
    elseif($DiskName)
    {$mask = $DiskName}
    else
    {$mask = "^$"}
    If ($PSCmdlet.ShouldProcess("Get disks from Ravello Repo"))
    {
        $disk = Invoke-RavRest @sRepo    
        $disk | where{$_.id -eq $DiskId -or $_.Name -like $mask} |
        ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_    
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Get-RavelloRepoVm
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'ComId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$CommunityId,
    [Parameter(Mandatory = $true,ParameterSetName = 'ComName')]
    [string]$CommunityName,
    [Parameter(ParameterSetName = 'ComId')]
    [Parameter(ParameterSetName = 'ComName')]
    [long]$VmId,
    [Parameter(ParameterSetName = 'ComId')]
    [Parameter(ParameterSetName = 'ComName')]
    [string]$VmName
  )
    
  Process
  {
    if($CommunityName)
    {
      $communities = Get-RavelloRepo
      $CommunityId = $communities |
      Where-Object{
        $_.name -eq $CommunityName
      } |
      Select-Object -ExpandProperty id
    }
    $sRepo = @{
      Method  = 'Get'
      Request = "communities/$($CommunityId)/images"
    }
    if($VmId -eq 0 -and !$VmName)
    {$mask = '*'}
    elseif($VmName)
    {$mask = $VmName}
    else
    {$mask = "^$"}
    If ($PSCmdlet.ShouldProcess("Get blueprint from Ravello Repo"))
    {
        $vm = Invoke-RavRest @sRepo    
        $vm | where{$_.id -eq $VmId -or $_.Name -like $mask} |
        ForEach-Object{
          $_.creationTime = ConvertFrom-JsonDateTime -DateTime $_.creationTime
          $_    
        }
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Copy-RavelloRepoBlueprint
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'BpId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$BlueprintId,
    [Parameter(Mandatory = $true,ParameterSetName = 'BpName')]
    [string]$BlueprintName,
    [string]$NewBlueprintName,
    [string]$Description
  )

  Process
  {
    if($BlueprintName)
    {
      $bp = Get-RavelloRepo | Get-RavelloRepoBlueprint -BlueprintName $BlueprintName
      $BlueprintId = $bp.id
    }
    elseif($BlueprintId)
    {
        $bp = Get-RavelloRepo | Get-RavelloRepoBlueprint -BlueprintId $BlueprintId
    }
    if(!$Description)
    {
        $Description = "Copy of $($bp.name)"
    }
    $sRepo = @{
      Method  = 'Post'
      Request = 'blueprints'
      Body    = @{
        blueprintId   = $bp.id
        blueprintName = $NewBlueprintName
        description   = $Description
        clearKeyPairs = $true
        offline       = ([string]$Offline).ToLower()
      }
    }
    If ($PSCmdlet.ShouldProcess("Copy blueprint from Repo"))
    {
        Invoke-RavRest @sRepo
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Copy-RavelloRepoDisk
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'DiskId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$DiskId,
    [Parameter(Mandatory = $true,ParameterSetName = 'DiskName')]
    [string]$DiskName,
    [string]$NewDiskName,
    [string]$Description
  )

  Process
  {
    if($DiskName)
    {
      $disk = Get-RavelloRepo | Get-RavelloRepoDisk -DiskName $DiskName
      $DiskId = $disk.id
    }
    elseif($DiskId)
    {
        $disk = Get-RavelloRepo | Get-RavelloRepoDisk -DiskId $DiskId
    }
    if(!$Description)
    {
        $Description = "Copy of $($disk.name)"
    }
    $sRepo = @{
      Method  = 'Post'
      Request = 'diskImages'
      Body    = @{
        diskImage   = @{
            description = $Description
            name = $NewDiskName
        }
        diskImageId = $disk.id
      }
    }
    If ($PSCmdlet.ShouldProcess("Copy disk from Repo"))
    {
        Invoke-RavRest @sRepo
    }
  }
}

# .ExternalHelp Ravello-Help.xml
function Copy-RavelloRepoVm
{
  [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory = $true,ParameterSetName = 'VmId',ValueFromPipelineByPropertyName)]
    [Alias('id')]
    [long]$VmId,
    [Parameter(Mandatory = $true,ParameterSetName = 'VmName')]
    [string]$VmName,
    [string]$NewVmName,
    [string]$Description
  )

  Process
  {
    if($VmName)
    {
      $vm = Get-RavelloRepo | Get-RavelloRepoVM -VmName $VmName
      $VmId = $vm.id
    }
    elseif($VmId)
    {
        $vm = Get-RavelloRepo | Get-RavelloRepoVM -VmId $VmId
    }
    if(!$Description)
    {
        $Description = "Copy of $($vm.name)"
    }
    $sRepo = @{
      Method  = 'Post'
      Request = 'images'
      Body    = @{
        blueprint     = $false
        imageId       = $vm.id
        imageName     = $NewVmName
        clearKeyPair  = $true
        offline       = $false
      }
    }
    If ($PSCmdlet.ShouldProcess("Copy VM from Repo"))
    {
        Invoke-RavRest @sRepo
    }
  }
}
#endregion

#region Extra
# .ExternalHelp Ravello-Help.xml
function Get-RavelloVmIso
{
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
    param(
      [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId')]
      [Parameter(ParameterSetName = 'VmName')]
      [Parameter(ParameterSetName = 'VmId')]
      [Alias('id')]
      [long]$ApplicationId,
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName')]
      [Parameter(ParameterSetName = 'VmName')]
      [Parameter(ParameterSetName = 'VmId')]
      [string]$ApplicationName,
      [Parameter(Mandatory = $true,ParameterSetName = 'VmName')]
      [string]$VmName,
      [Parameter(Mandatory = $true,ParameterSetName = 'VmId')]
      [long]$VmId,
      [string]$DeviceName = 'cdrom'
    )

    Process
    {
        $sVmCD = @{}
        $PSBoundParameters.GetEnumerator() |
        where{$_.Key -notmatch "^DeviceName"} |
        ForEach-Object{
          $sVmCD.Add($_.Key,$_.Value)
        }
        $vm = Get-RavelloVM @sVmCD
        $vm.hardDrives | where{$_.type -eq 'CDROM' -and $_.name -match $DeviceName} | %{
            If ($PSCmdlet.ShouldProcess("Get connected ISO"))
            {
                Get-RavelloDiskImage -DiskImageId $_.baseDiskImageId
            }
        }
    }
}

# .ExternalHelp Ravello-Help.xml
function Set-RavelloVmIso
{
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Low')]
    param(
      [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId-VmId-IsoId')]
      [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId-VmId-IsoName')]
      [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId-VmName-IsoId')]
      [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName,ParameterSetName = 'AppId-VmName-IsoName')]
      [Alias('id')]
      [long]$ApplicationId,
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-IsoId')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-IsoName')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-IsoId')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-IsoName')]
      [string]$ApplicationName,
      [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-IsoId')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-IsoName')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-IsoId')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-IsoName')]
      [long]$VmId,
      [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName-IsoId')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName-IsoName')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-IsoId')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-IsoName')]
      [string]$VmName,
      [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-IsoId')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName-IsoId')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-IsoId')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-IsoId')]
      [long]$DiskImageId,
      [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmId-IsoName')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppId-VmName-IsoName')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmId-IsoName')]
      [Parameter(Mandatory = $true,ParameterSetName = 'AppName-VmName-IsoName')]
      [string]$DiskImageName,
      [Parameter(ParameterSetName = 'AppId-VmId-IsoId')]
      [Parameter(ParameterSetName = 'AppId-VmId-IsoName')]
      [Parameter(ParameterSetName = 'AppId-VmName-IsoId')]
      [Parameter(ParameterSetName = 'AppId-VmName-IsoName')]
      [Parameter(ParameterSetName = 'AppName-VmId-IsoId')]
      [Parameter(ParameterSetName = 'AppName-VmId-IsoName')]
      [Parameter(ParameterSetName = 'AppName-VmName-IsoId')]
      [Parameter(ParameterSetName = 'AppName-VmName-IsoName')]
      [string]$DeviceName = 'cdrom'
    )

    Process
    {
        $sApp = @{
            Raw = $true
        }
        $PSBoundParameters.GetEnumerator() | 
        where{$_.Key -match "^Application"} |
        ForEach-Object{
          $sApp.Add($_.Key,$_.Value)
        }
        $app = Get-RavelloApplication @sApp

        $sImg = @{}
        $PSBoundParameters.GetEnumerator() | 
        where{$_.Key -match "^DiskImage"} |
        ForEach-Object{
          $sImg.Add($_.Key,$_.Value)
        }
        $img = Get-RavelloDiskImage @sImg

        $newVm = @()
        foreach($vm in $app.design.vms){
            if($vm.Name -eq $VmName -or $vm.id -eq $VmId){
                $newDev = @()
                foreach($dev in $vm.hardDrives){
                    if($dev.type -eq 'CDROM' -and $dev.name -match $DeviceName){
                        $dev.size.value = $img.size.value
                        $dev.size.unit = $img.size.unit
                        Add-Member -InputObject $dev -Name 'baseDiskImageId' -Value $img.id -MemberType NoteProperty
                        Add-Member -InputObject $dev -Name 'baseDiskImageName' -Value $img.name -MemberType NoteProperty
                    }
                    $newDev += $dev
                }
                $vm.hardDrives = $newDev
            }
            $newVm += $vm
        }
        $app.design.vms = $newVm
        $sApp = @{
            Method  = 'Put'
            Request = "applications/$($app.id)"
            Body    = $app
        }
        If ($PSCmdlet.ShouldProcess("Connect ISO to VM"))
        {
            Invoke-RavRest @sApp
        }
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