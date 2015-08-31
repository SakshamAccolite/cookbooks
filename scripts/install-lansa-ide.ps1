﻿<#
.SYNOPSIS

Install the LANSA IDE.
Creates a SQL Server Database then installs from the DVD image

Requires the environment that a LANSA Cake provides, particularly an AMI license.

# N.B. It is vital that the user id and password supplied pass the password rules. 
E.g. The password is sufficiently complex and the userid is not duplicated in the password. 
i.e. UID=PCXUSER and PWD=PCXUSER@#$%^&* is invalid as the password starts with the entire user id "PCXUSER".

.EXAMPLE


#>
param(
[String]$server_name=$env:COMPUTERNAME,
[String]$dbname='LANSA',
[String]$dbuser = 'administrator',
[String]$dbpassword = 'password',
[String]$webuser = 'PCXUSER2',
[String]$webpassword = 'PCXUSER@122',
[String]$f32bit = 'true',
[String]$SUDB = '1',
[String]$UPGD = 'true',
[String]$maxconnections = '20',
[String]$wait
)

# If environment not yet set up, it should be running locally, not through Remote PS
if ( -not $script:IncludeDir)
{
    # Log-Date can't be used yet as Framework has not been loaded

	Write-Output "Initialising environment - presumed not running through RemotePS"
	$MyInvocation.MyCommand.Path
	$script:IncludeDir = Split-Path -Parent $MyInvocation.MyCommand.Path

	. "$script:IncludeDir\Init-Baking-Vars.ps1"
	. "$script:IncludeDir\Init-Baking-Includes.ps1"
}
else
{
	Write-Output "$(Log-Date) Environment already initialised - presumed running through RemotePS"
}

# Put first output on a new line in cfn_init log file
Write-Output ("`r`n")

$trusted=$true

Write-Debug ("Server_name = $server_name")
Write-Debug ("dbname = $dbname")
Write-Debug ("dbuser = $dbuser")
Write-Debug ("webuser = $webuser")
Write-Debug ("32bit = $f32bit")
Write-Debug ("SUDB = $SUDB")
Write-Debug ("UPGD = $UPGD")

try
{
    if ( $f32bit -eq 'true' -or $f32bit -eq '1')
    {
        $f32bit_bool = $true
    }
    else
    {
        $f32bit_bool = $false
    }

    if ( $UPGD -eq 'true' -or $UPGD -eq '1')
    {
        $UPGD_bool = $true
    }
    else
    {
        $UPGD_bool = $false
    }

    Write-Debug ("UPGD_bool = $UPGD_bool" )

    $x_err = (Join-Path -Path $ENV:TEMP -ChildPath 'x_err.log')
    Remove-Item $x_err -Force -ErrorAction SilentlyContinue

    # On initial install disable TCP Offloading

    if ( -not $UPGD_bool )
    {
        Disable-TcpOffloading
    }

    ######################################
    # Require MS C runtime to be installed
    ######################################

    if ( -not $UPGD_bool )
    {
        Write-Output ("$(Log-Date) Ensure SQL Server Powershell module is loaded.")

        Write-Verbose ("Loading this module changes the current directory to 'SQLSERVER:\'. It will need to be changed back later")

        Import-Module “sqlps” -DisableNameChecking

        if ( $SUDB -eq '1' -and -not $UPGD_bool)
        {
            Create-SqlServerDatabase $server_name $dbname
        }

        #####################################################################################
        Write-Output ("$(Log-Date) Enable Named Pipes on database")
        #####################################################################################

        if ( Change-SQLProtocolStatus -server $server_name -instance "MSSQLSERVER" -protocol "NP" -enable $true )
        {
            $service = get-service "MSSQLSERVER"  
            restart-service $service.name -force #Restart SQL Services 
        }

        Write-Verbose ("Change current directory from 'SQLSERVER:\' back to the file system so that file pathing works properly")
        cd "c:"
    }

    if ( -not $UPGD_bool )
    {
        Start-WebAppPool -Name "DefaultAppPool"

        # Speed up the start of the VL IDE
        # Switch off looking for software license keys

        [Environment]::SetEnvironmentVariable('LSFORCEHOST', 'NO-NET', 'Machine')
    }

    if ($f32bit_bool)
    {
        $APPA = "${ENV:ProgramFiles(x86)}\LANSA"
    }
    else
    {
        $APPA = "${ENV:ProgramFiles}\LANSA"
    }

    #####################################################################################
    Write-Output ("$(Log-Date) Pull down DVD image ")
    #####################################################################################

    cmd /c aws s3 sync  "s3://lansa/releasedbuilds/v13/LanDVDcut_L4W13200_4088_latest" $Script:DvdDir "--exclude" "*ibmi/*" "--exclude" "*AS400/*" "--exclude" "*linux/*" "--exclude" "*setup/Installs/MSSQLEXP/*" "--delete" | Write-Output
    if ( $LastExitCode -ne 0 )
    {
        throw
    }

    if ( $UPGD_bool )
    {
        #####################################################################################
        Write-Output ("$(Log-Date) Installing all EPCs")
        #####################################################################################

        cmd /c $Script:DvdDir\EPC\allepcs.exe """$APPA""" | Write-Output
        if ( $LastExitCode -ne 0 )
        {
            throw
        }        
    }
    else
    {
        #####################################################################################
        Write-Output ("$(Log-Date) Installing the application")
        #####################################################################################

        Install-VisualLansa
    }

    #####################################################################################
    Write-Output ("$(Log-Date) Pull down latest Integrator updates")
    #####################################################################################

    cmd /c "$APPA\integrator\jsmadmin\strjsm.exe" "-sstop"
    cmd /c aws s3 sync  "s3://lansa/releasedbuilds/v13/Integrator_L4W13200_latest" "$APPA\Integrator" | Write-Output
    if ( $LastExitCode -ne 0 )
    {
        throw
    }
    cmd /c "$APPA\integrator\jsmadmin\strjsm.exe" "-sstart"

    Write-Output "$(Log-Date) IDE Installation completed"
    Write-Output ""

    #####################################################################################
    Write-Output ("$(Log-Date) Test if post install x_run processing had any fatal errors")
    #####################################################################################

    if ( (Test-Path -Path $x_err) )
    {
        Write-Verbose ("Signal to caller that the installation has failed")

        $errorRecord = New-ErrorRecord System.Configuration.Install.InstallException RegionDoesNotExist `
            NotInstalled $region -Message "$x_err exists which indicates an installation error has occurred."
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }


    if ( -not $UPGD_bool )
    {
        #####################################################################################
        Write-Output ("$(Log-Date) Import test case")
        #####################################################################################

        # Note: have not been able to find a way to pass a parameter with spaces in and NOT have the entire parameter surrounded by quotes by Powershell
        # So $import path must not have spaces in it.

        $import = "$script:IncludeDir\..\Tests\WAMTest"
        $x_dir = "$APPA\x_win95\x_lansa\execute"
        cd $x_dir
        cmd /c "x_run.exe" "PROC=*LIMPORT" "LANG=ENG" "PART=DEX" "USER=$webuser" "DBIT=MSSQLS" "DBII=$dbname" "DBTC=Y" "ALSC=NO" "BPQS=Y" "EXPR=$import" "LOCK=NO" | Write-Output

        if ( $LastExitCode -ne 0 -or (Test-Path -Path $x_err) )
        {
            Write-Verbose ("Signal to caller that the import has failed")

            $errorRecord = New-ErrorRecord System.Configuration.Install.InstallException RegionDoesNotExist `
                NotInstalled $region -Message "$x_err exists or an exception has been thrown which indicate an installation error has occurred whilst importing $import."
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        #####################################################################################
        # License mapping needs to occur once final instance is instantiated. Hence
        # this is all commented out
	    # Write-output ("$(Log-Date) Remap licenses to new instance Guid and set permissions so that webuser may access them" )
        #####################################################################################

	    # Map-LicenseToUser "LANSA Scalable License" "ScalableLicensePrivateKey" $webuser
	    # Map-LicenseToUser "LANSA Integrator License" "IntegratorLicensePrivateKey" $webuser
	    # Map-LicenseToUser "LANSA Development License" "DevelopmentLicensePrivateKey" $webuser

        #####################################################################################
        Write-output ("$(Log-Date) Shortcuts")
        #####################################################################################

        New-Shortcut "C:\Program Files\Internet Explorer\iexplore.exe" "Desktop\Start Here.lnk" -Description "Start Here"  -Arguments "file://$Script:DvdDir/setup/CloudStartHere.htm" -WindowStyle "Maximized"
        New-Shortcut "C:\Program Files\Internet Explorer\iexplore.exe" "Desktop\Education.lnk" -Description "Education"  -Arguments "http://www.lansa.com/education/" -WindowStyle "Maximized"
        New-Shortcut "$Script:DvdDir\setup\LansaQuickConfig.exe" "Desktop\Lansa Quick Config.lnk" -Description "Quick Config"
        New-Shortcut "$ENV:SystemRoot\system32\WindowsPowerShell\v1.0\powershell.exe" "Desktop\Install EPCs.lnk" -Description "Install EPCs" -Arguments "-ExecutionPolicy Bypass -Command ""c:\lansa\Scripts\install-lansa-ide.ps1 -upgd true"""

        # Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "QuickConfig" -Value "$Script:DvdDir\setup\LansaQuickConfig.exe"
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "StartHere" -Value "c:\Users\Administrator\Desktop\Start Here.lnk"

        Add-TrustedSite "lansa.com"
        Add-TrustedSite "google-analytics.com"
        Add-TrustedSite "googleadservices.com"
        Add-TrustedSite "img.en25.com"
        Add-TrustedSite "addthis.com"
    }

    Write-Output ("$(Log-Date) Installation completed successfully")
}
catch
{
	$_
    Write-Error ("$(Log-Date) Installation error")
    throw
}
finally
{
    Write-Output ("$(Log-Date) See LansaInstallLog.txt and other files in $ENV:TEMP for more details.")

    # Wait if we are upgrading so the user can see the results
    if ( $UPGD_bool )
    {
        Write-Output ""
        Write-Output "Press any key to continue ..."

        $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

# Successful completion so set Last Exit Code to 0
cmd /c exit 0
