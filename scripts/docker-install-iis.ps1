﻿# presumes that these directories exist:
# c:\temp mapped to host temporary directory
# c:\scripts to host  Cookbooks\scripts
# c:\lansa container directory for the msi location

try {
    Push-Location

    [Environment]::SetEnvironmentVariable("TMP", "c:\temp", "Process")
    [Environment]::SetEnvironmentVariable("TEMP", "c:\temp", "Process")

    # If environment not yet set up, it should be running locally, not through Remote PS
    if ( -not $script:IncludeDir)
    {
        # Log-Date can't be used yet as Framework has not been loaded

        Write-Host "Initialising environment - presumed not running through RemotePS"
        $MyInvocation.MyCommand.Path
        $script:IncludeDir = Split-Path -Parent $MyInvocation.MyCommand.Path

        . "$script:IncludeDir\Init-Baking-Vars.ps1"
        . "$script:IncludeDir\Init-Baking-Includes.ps1"
    }
    else
    {
        Write-Host "$(Log-Date) Environment already initialised - presumed running through RemotePS"
    }

    Write-Host ("Install Visual C Runtime 32-bit for VS 2015, 2017, 2019")
    start-process -FilePath "$script:IncludeDir\..\installs\vc_redist\vcredist_x86.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait

    Write-Host ("Install Visual C Runtime 64-bit for VS 2015, 2017, 2019")
    start-process -FilePath "$script:IncludeDir\..\installs\vc_redist\vcredist_x64.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait

    Write-Host ("Install Visual C Runtime 32-bit for VS 2013")
    start-process -FilePath "$script:IncludeDir\..\installs\vc_redist\vcredist_x86_2013.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait

    Write-Host ("Install Visual C Runtime 64-bit for VS 2013")
    start-process -FilePath "$script:IncludeDir\..\installs\vc_redist\vcredist_x64_2013.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait

    Write-Output "Installing IIS"
    import-module servermanager
    install-windowsfeature web-server

    Write-Output "Enabling Remote IIS Management"
    install-windowsfeature web-mgmt-service
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WebManagement\Server -Name EnableRemoteManagement -Value 1
    Set-Service -name WMSVC -StartupType Automatic
    Start-service WMSVC

    Write-Output "Turning off complex password requirements"
    secedit /export /cfg c:\secpol.cfg
    (Get-Content C:\secpol.cfg).replace("PasswordComplexity = 1", "PasswordComplexity = 0") | Out-File C:\secpol.cfg
    secedit /configure /db c:\windows\security\local.sdb /cfg c:\secpol.cfg /areas SECURITYPOLICY
    Remove-Item -force c:\secpol.cfg -confirm:$false

    Write-Output "Create local user test (pwd=test)"
    NET USER test "test" /ADD
    NET LOCALGROUP "Administrators" "test" /ADD

    Write-Output "Set LANSA Cloud registry entries"
    $lansaKey = 'HKLM:\Software\LANSA\'
    if (!(Test-Path -Path $lansaKey)) {
       New-Item -Path $lansaKey
    }
    New-ItemProperty -Path $lansaKey  -Name 'Cloud' -PropertyType String -Value 'Docker' -Force

    # add-odbcdsn -name trunk -DriverName "ODBC Driver 13 for SQL Server" -setPropertyValue @("Server=robgw10","Trusted_Connection=No", "Database=Trunk") -Platform "32-bit" -DsnType "System"

    .\install-lansa-base.ps1 'dummy' $ENV:TEMP 'dummy' 'dummy'

    # New-Item -ItemType directory -Path C:\lansa -Force

    # Write-Output ("Copying Files")

    if ( $false -eq $true) {
        # Temporarily copy in Windows System DLLs
        # Copy current versions rather than the contents of a temporary directory which will become out of date

        Set-Location c:\windows\syswow64

        Remove-Item aepic.dll  -ErrorAction SilentlyContinue
        Remove-Item avifil32.dll  -ErrorAction SilentlyContinue
        Remove-Item avifil32.dll.mui  -ErrorAction SilentlyContinue
        Remove-Item avrt.dll  -ErrorAction SilentlyContinue
        Remove-Item chakra.dll  -ErrorAction SilentlyContinue
        Remove-Item comppkgsup.dll -ErrorAction SilentlyContinue
        Remove-Item coreuicomponents.dll  -ErrorAction SilentlyContinue
        Remove-Item cryptngc.dll  -ErrorAction SilentlyContinue
        Remove-Item dcomp.dll  -ErrorAction SilentlyContinue
        Remove-Item devmgr.dll  -ErrorAction SilentlyContinue
        Remove-Item dmpushproxy.dll  -ErrorAction SilentlyContinue
        Remove-Item dsreg.dll  -ErrorAction SilentlyContinue
        Remove-Item edputil.dll  -ErrorAction SilentlyContinue
        Remove-Item efsadu.dll  -ErrorAction SilentlyContinue
        Remove-Item efswrt.dll  -ErrorAction SilentlyContinue
        Remove-Item elscore.dll  -ErrorAction SilentlyContinue
        Remove-Item ieadvpack.dll  -ErrorAction SilentlyContinue
        Remove-Item ieapfltr.dll  -ErrorAction SilentlyContinue
        Remove-Item ieframe.dll  -ErrorAction SilentlyContinue
        Remove-Item ieui.dll  -ErrorAction SilentlyContinue
        Remove-Item imgutil.dll  -ErrorAction SilentlyContinue
        Remove-Item inetcomm.dll  -ErrorAction SilentlyContinue
        Remove-Item iri.dll  -ErrorAction SilentlyContinue
        Remove-Item mfplat.dll  -ErrorAction SilentlyContinue
        Remove-Item msacm32.dll  -ErrorAction SilentlyContinue
        Remove-Item msfeeds.dll  -ErrorAction SilentlyContinue
        Remove-Item mshtml.dll  -ErrorAction SilentlyContinue
        Remove-Item msoert2.dll  -ErrorAction SilentlyContinue
        Remove-Item occache.dll  -ErrorAction SilentlyContinue
        Remove-Item omadmapi.dll  -ErrorAction SilentlyContinue
        Remove-Item onex.dll  -ErrorAction SilentlyContinue
        Remove-Item policymanager.dll  -ErrorAction SilentlyContinue
        Remove-Item rtworkq.dll  -ErrorAction SilentlyContinue
        Remove-Item shdocvw.dll  -ErrorAction SilentlyContinue
        Remove-Item tapi32.dll  -ErrorAction SilentlyContinue
    }

    # Set-Location c:\HostSystem

    if ( $false -eq $true) {
        # lansa.wix.customactions.dll
        Copy-Item oledlg.dll c:\windows\syswow64

        # x_prim.dll
        Copy-Item avifil32.dll c:\windows\syswow64
        Copy-Item msvfw32.dll c:\windows\syswow64
        Copy-Item msacm32.dll c:\windows\syswow64
    }

    # The following DLLs are thought to not be required.


    if ( $false -eq $true) {
        Write-Output ("Should do this")
       Copy-Item aepic.dll c:\windows\syswow64
       Copy-Item avifil32.dll c:\windows\syswow64
       Copy-Item en-US\avifil32.dll.mui c:\windows\syswow64
    }

    if ( $false -eq $true) {
        Write-Output ("One")
       Copy-Item avrt.dll c:\windows\syswow64
       Copy-Item chakra.dll c:\windows\syswow64
       Copy-Item comppkgsup.dll c:\windows\syswow64
       Copy-Item coreuicomponents.dll c:\windows\syswow64
    }

    if ( $false -eq $true) {
    Write-Output ("Two")
       Copy-Item cryptngc.dll c:\windows\syswow64
       Copy-Item dcomp.dll c:\windows\syswow64
       Copy-Item devmgr.dll c:\windows\syswow64
       Copy-Item dmpushproxy.dll c:\windows\syswow64
       Copy-Item dsreg.dll c:\windows\syswow64
       Copy-Item edputil.dll c:\windows\syswow64
       Copy-Item efsadu.dll c:\windows\syswow64
       Copy-Item efswrt.dll c:\windows\syswow64
       Copy-Item elscore.dll c:\windows\syswow64

    }

    if ( $false -eq $true) {
        Write-Output ("Should do this too")
       Copy-Item ieadvpack.dll c:\windows\syswow64
       Copy-Item ieapfltr.dll c:\windows\syswow64
       Copy-Item ieframe.dll c:\windows\syswow64
       Copy-Item ieui.dll c:\windows\syswow64
       Copy-Item imgutil.dll c:\windows\syswow64
       Copy-Item inetcomm.dll c:\windows\syswow64
       Copy-Item iri.dll c:\windows\syswow64

       Copy-Item mfplat.dll c:\windows\syswow64
    }

    if ( $false -eq $true) {
        Write-Output ("Not needed for x_comp.dll")
       Copy-Item msfeeds.dll c:\windows\syswow64
       Copy-Item mshtml.dll c:\windows\syswow64
       Copy-Item msoert2.dll c:\windows\syswow64

       Copy-Item occache.dll c:\windows\syswow64
       Copy-Item omadmapi.dll c:\windows\syswow64
       Copy-Item onex.dll c:\windows\syswow64
       Copy-Item policymanager.dll c:\windows\syswow64
       Copy-Item rtworkq.dll c:\windows\syswow64
       Copy-Item shdocvw.dll c:\windows\syswow64
       Copy-Item tapi32.dll c:\windows\syswow64
    }
} catch {
    $_ | Out-default | Write-Host
    Write-Error ("Failed")
} finally {
    Pop-Location
    Write-Output ("Finished")
}
