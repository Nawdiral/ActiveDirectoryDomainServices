<#
  This script will link WMI Filters to GPOs. It gets this information from
  the manifest.xml file of the GPO backup.

  Prerequisites:
    - Group Policies have been imported
    - WMI Filters have been imported

  Syntax examples:
    LinkWMIFilters.ps1 -BackupLocation c:\Backups\GPOs

  It is based on the following script by Microsoft's Manny Murguia:
    - Bulk Import of Group Policy Objects between Different Domains with PowerShell:
      http://blogs.technet.com/b/manny/archive/2012/02/12/bulk-import-of-group-policy-objects-between-different-domains-with-powershell.aspx

  Release 1.1
  Written by Jeremy@jhouseconsulting.com 13th September 2013
  Modified by Jeremy@jhouseconsulting.com 29th January 2014
#>

#-------------------------------------------------------------
param([String]$BackupLocation,[String]$LogFile);

# Get the script path
$ScriptPath = {Split-Path $MyInvocation.ScriptName}

if ([String]::IsNullOrEmpty($BackupLocation))
{
    $BackupLocation = $(&$ScriptPath) + "\GPOs\Backups";
}

$Manifest = $BackupLocation + "\manifest.xml";

if ([String]::IsNullOrEmpty($LogFile))
{
    $LogFile = $(&$ScriptPath) + "\LinkWMIFilters.txt";
}
set-content $LogFile $NULL;

#-------------------------------------------------------------
Write-Host -ForegroundColor Green "Importing the PowerShell modules..."

# Import the Active Directory Module
Import-Module ActiveDirectory -WarningAction SilentlyContinue
if($Error.Count -eq 0) {
   #Write-Host "Successfully loaded Active Directory Powershell's module" -ForeGroundColor Green
}else{
   Write-Host "Error while loading Active Directory Powershell's module : $Error" -ForeGroundColor Red
   exit
}

# Import the Group Policy Module
Import-Module GroupPolicy -WarningAction SilentlyContinue
if($Error.Count -eq 0) {
   #Write-Host "Successfully loaded Group Policy Powershell's module" -ForeGroundColor Green
}else{
   Write-Host "Error while loading Group Policy Powershell's module : $Error" -ForeGroundColor Red
   exit
}
write-host " "

#-------------------------------------------------------------

$myDomain = [System.Net.NetworkInformation.IpGlobalProperties]::GetIPGlobalProperties().DomainName;
$DomainDn = "DC=" + [String]::Join(",DC=", $myDomain.Split("."));
$SystemContainer = "CN=System," + $DomainDn;
$GPOContainer = "CN=Policies," + $SystemContainer;
$WMIFilterContainer = "CN=SOM,CN=WMIPolicy," + $SystemContainer;

try
{
    if (![System.DirectoryServices.DirectoryEntry]::Exists("LDAP://" + $DomainDN))
    {
        write-host -ForegroundColor Red "Could not connect to LDAP path $DomainDN";
        write-host -ForegroundColor Red "Exiting Script";
        return;
    }
}
catch
{
        write-host -ForegroundColor Red "Could not connect to LDAP path $DomainDN";
        write-host -ForegroundColor Red "Exiting Script";
        return;
}

# Get the current date
get-Date | Out-File $LogFile

[xml]$ManifestData = get-content $Manifest

foreach ($item in $ManifestData.Backups.BackupInst) {
  $WMIFilterDisplayName = $NULL;
  $GPReportPath = $BackupLocation + "\" + $item.ID."#cdata-section" + "\gpreport.xml";
  [xml]$GPReport = get-content $GPReportPath;
  $WMIFilterDisplayName = $GPReport.GPO.FilterName;
  if ($WMIFilterDisplayName -ne $NULL) {
    $GPOName = $GPReport.GPO.Name;
    $GPO = Get-GPO $GPOName;
    $WMIFilter = Get-ADObject -Filter 'msWMI-Name -eq $WMIFilterDisplayName';
    $WMIFilterName = $WMIFilter.Name;
    $GPODN = "CN={" + $GPO.Id + "}," + $GPOContainer;
    $WMIFilterLinkValue = "[$myDomain;" + $WMIFilterName + ";0]";
    Try {
        Set-ADObject $GPODN -Add @{gPCWQLFilter=$WMIFilterLinkValue};
      }
    Catch {
        # Under some situations I've found that Set-ADObject will fail with the error: 
        # "Multiple values were specified for an attribute that can have only one value".
        # So we capture the error and retry using the -Replace parameter instead of the
        # -Add parameter.
        Set-ADObject $GPODN -Replace @{gPCWQLFilter=$WMIFilterLinkValue};
      }
    $Message = "The '$WMIFilterDisplayName' WMI Filter has been linked to the following GPO: $GPOName"
    write-host -ForeGroundColor Green $Message
    $Message | Out-File $LogFile -append
  }
}

write-host -ForeGroundColor Green "`nA log file of all WMI filters linked has been save here: $LogFile"
