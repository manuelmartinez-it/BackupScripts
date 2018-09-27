<#

==========================================================================
Script: BackupVcsaVro.ps1
Created on: 09/19/2018
Created by: Manuel Martinez
Github: https://www.github.com/manuelmartinez-it
Twitter: @ManuelM_IT
===========================================================================

.SYNOPSIS
    Create a file level backup of the VCSA appliance or PSC
.NOTES
    Author:  Manuel Martinez
    Github: https://www.github.com/manuelmartinez-it
.NOTES
    Update the appropriate local variables for your environment
    REQUIRES: External Functions located on my GitHub in ModularFunctions/PowerShell
    User must be a part of ‘SystemConfiguration.Administrators’ SSO Group in vCenter
    If you receive 'Unable to authorize user' message restart the following service in the appliance 'applmgmt (VMware Appliance Management Service)'
.EXAMPLE
  BackupVcsaVro.ps1

#>

#region Call External Fuctions

    # External Functions needed to run script
    . C:\Scripts\Functions\fn_Set-PsEmailFormatting.ps1
    . C:\Scripts\Functions\fn_Remove-OldFolders.ps1
    Import-Module VMware.VimAutomation.Cis.Core

#endregion


#region Local Variables

    # Credential information
    $user = 'service.vro@company.com'
    $passwordFile = 'c:\scripts\Service.vRO.txt'
    $keyfile = 'C:\scripts\Service.vRO.key'
    $key = Get-Content $keyfile
    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, (Get-Content $passwordFile | ConvertTo-SecureString -Key $key)
    $password = $credential.GetNetworkCredential().Password
    [VMware.VimAutomation.Cis.Core.Types.V1.Secret]$locationPassword=$password

    # Backup information
    $todaysDate = Get-Date -UFormat %Y-%m-%d
    $locationType = 'FTPS'
    $vcsa = "vcsa.company.com"
    $backupServer = 'ftps-server.company.com'
    $backupLocation = "$backupServer/VCSA/$vcsa"
    $deleteLocation = "$backupServer\VCSA\$vcsa"
    $daysOld = 7
    $comment = "Daily backup of $vcsa created on $todaysDate"

    # Email information
    $smtp = 'webmail.company.com'
    $sentFrom = 'vROnotifications@company.com'
    $sendTo = 'me.here@company.com'
    $subject = "VCSA file backup failed - $vcsa"
    $header = "VCSA file backup information - $vcsa"

#endregion


#region Do El Work

    # Login to the CIS Service of the desired VCSA
    Connect-CisServer -Server $vcsa -Credential $credential

    # Store the Backup Job Service into a variable
    $backupJobSvc = Get-CisService -Name com.vmware.appliance.recovery.backup.job

    # Create a specification based on the Help response
    $backupSpec = $backupJobSvc.Help.create.piece.Create()

    # Fill in each input parameter, as needed
    $backupSpec.parts = @("common")
    $backupSpec.location_type = $locationType
    $backupSpec.location = "$backupLocation/vcsa-$todaysDate"
    $backupSpec.location_user = $user
    $backupSpec.location_password = $locationPassword
    $backupSpec.comment = $comment

    # Create the backup job and save to variable
    $job = $backupJobSvc.create($backupSpec)

    # Wait 20 seconds for backup to start before getting status
    Start-Sleep -Seconds 20

    # Get the backup job Id
    $jobId = $backupJobSvc.get($job.id)

    # Trim Backup Job Status information
    $jobInfo = [pscustomobject]@{
        ID = $jobId.id
        State = $jobId.state
        Progress = $jobId.progress
        StartTime = $jobId.start_time
        Message = $jobId.messages.default_message
    }
    
    # Check the status of the backup job and email if job failed
    if($jobId.state -eq 'FAILED'){
        Set-PsEmailFormatting -SmtpServer $smtp -SenderEmail $sentFrom -RecipientEmail $sendTo -EmailSubject $subject -BodyHeader $header -TableInfo $jobInfo
    }

    # Disconnect from the CIS Service of the desired VCSA
    Disconnect-CisServer -Confirm:$false

    # Remove folders older than 7 Days
    New-PSDrive -Name VCSA -PSProvider FileSystem -Root "\\$deleteLocation" -Credential $credential | Out-Null
    Remove-OldFolders -FolderLocation VCSA:\ -DaysOld $daysOld

#endregion

