#Gets a list of relivent Okta/AS user classes and exports them to a CSV


$DisabledUsersOU1 = "OU=_Disabled Users,OU=Lab,DC=Lab,DC=LOCAL"
$DisabledUsersOU2 = "OU=Users,OU=Tombstoned,DC=Lab,DC=LOCAL"
$DisabledUsersOU3 = "OU=Tombstoned,DC=Lab,DC=LOCAL"

$CurrentUserDocsPath = [Environment]::GetFolderPath("MyDocuments")

$Session = New-PSSession -Credential $(Get-Credential) -ComputerName "TEMP-DC"
$AllADuser = Invoke-Command -Session $Session -ScriptBlock { Get-ADUser -Filter 'enabled -eq $true' -Properties mail | Select-Object *, @{l = 'Parent'; e = { (New-Object 'System.DirectoryServices.directoryEntry' "LDAP://$($_.DistinguishedName)").Parent } } }

Import-module AzureAD #If you're from the future, this may not work and needs to be modified to use Graph instead of this module
Connect-AzureAD
Write-host "Getting Azure AD users"
$AZUsers = Get-AzureADUser -all $true | Where-Object { $_.dirsyncenabled -like "true" }

Write-Host "Writing first object"
$OnPremWithImmutableID = for ($i = 0; $i -lt $AllADuser.length; $i++) {   
    [PSCustomObject]@{
        Name              = $AllADuser.Name[$i]
        UserPrincipalName = $AllADuser.UserPrincipalName[$i]
        objectGUID        = $AllADuser[$i]
        mail              = $AllADuser.mail[$i]
        ImmutableID       = [system.convert]::ToBase64String(($AllADuser.ObjectGUID[$i]).ToByteArray()) #Modify AD presented GUID to match Azure GUID presentation
        DistinguishedName = $AllADuser[$i].Parent.substring(7)
    }
}

Write-Host "Getting users that are in Azure but not on-prem"
$AzureUsersWithNoOnPremGuid = for ($i = 0; $i -lt $AllADuser.length; $i++) {  
    if ($OnPremWithImmutableID.ImmutableID -notcontains $AZusers[$i].ImmutableID) {
        [PSCustomObject]@{
            Name = $AZusers.DisplayName[$i]
            UPN  = $AZUsers.UserPrincipalName[$i]

        }
    }
}
Write-Host "Writing 3rd object"
$ExpectedDeletedUsers = for ($i = 0; $i -lt $AllADuser.length; $i++) {
    
    if ((($OnPremWithImmutableID.DistinguishedName[$i] -eq $DisabledUsersOU1) -or ($OnPremWithImmutableID.DistinguishedName[$i] -eq $DisabledUsersOU2) -or ($OnPremWithImmutableID.DistinguishedName[$i] -eq $DisabledUsersOU3))) {
        [PSCustomObject]@{
            Name              = $OnPremWithImmutableID.Name[$i]
            UserPrincipalName = $OnPremWithImmutableID.UserPrincipalName[$i]
            objectGUID        = $OnPremWithImmutableID[$i]
            mail              = $OnPremWithImmutableID.mail[$i]
            ImmutableID       = $OnPremWithImmutableID.ImmutableID[$i]
            DistinguishedName = $OnPremWithImmutableID.DistinguishedName[$i]
        }
    }
}

$ADUserWithNoAzureGuid = for ($i = 0; $i -lt $AllADuser.length; $i++) {  
    if ( $AZusers.ImmutableID -notcontains $OnPremWithImmutableID.ImmutableID[$i]) {
        [PSCustomObject]@{
            Name = $AZusers.DisplayName[$i]
            UPN  = $AZUsers.UserPrincipalName[$i]

        }
    }
}

Write-Host "There are $($AzureUsersWithNoOnPremGuid.count) users in Azure that do not have an on-prem GUID"
Write-Host "There are $($ExpectedDeletedUsers.count) users in AD that are disabled or tombstoned"
Write-host "There are $($ADUserWithNoAzureGuid.count) users in AD that do not have an Azure GUID"
$OnPremWithImmutableID | Export-Csv -Path "$($CurrentUserDocsPath)\OnPremWithImmutableID.csv" -NoTypeInformation -Force
$AzureUsersWithNoOnPremGuid | Export-Csv -Path "$($CurrentUserDocsPath)\AzureUsersWithNoOnPremGuid.csv" -NoTypeInformation -Force
$ExpectedDeletedUsers | Export-Csv -Path "$($CurrentUserDocsPath)\ExpectedDeletedUsers.csv" -NoTypeInformation -Force