$RemoteServer = "lab-util.lab.local"
$Session = New-PSsession -ComputerName $RemoteServer -Credential (Get-Credential)
$LogonUPN = Read-Host "Enter your email"
Connect-ExchangeOnline -UserPrincipalName $LogonUPN
#Note, mailNickname must be set to username for this to all work
$Users = Invoke-Command -Session $Session -ScriptBlock {
    $Users = Get-ADUser -filter {(Enabled -eq $False)} -ResultPageSize 1000 -Properties *
    return $Users
    }

foreach ($User in $Users){
    set-mailbox -identity $User.mail -HiddenFromAddressListsEnabled $true -whatif
}
