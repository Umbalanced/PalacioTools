$MailDomain = "@PalacioTech.io"
$OnMicrosoftDomain = "@PalacioTech.onmicrosoft.com"

Connect-ExchangeOnline
 $deletedmailboxes = Get-Mailbox -SoftDeletedMailbox #Get all deleted mailboxes
 foreach ($mailbox in $deletedmailboxes)
 {
    $MailboxAddress = $mailbox.Alias + $MailDomain #Create mailbox address
    Write-Host "Restoring $MailboxAddress"
    New-Mailbox -Shared -Name $mailbox.Name -DisplayName $mailbox.name -Alias $mailbox.Alias | Out-Null #Create the new shared mailbox to restore to
    Set-Mailbox -identity $($mailbox.Alias + $OnMicrosoftDomain) -WindowsEmailAddress $MailboxAddress | Out-Null #add primary smtp address
    Write-Host "Waiting 30 seconds for mailbox to be created"
    Start-Sleep -Seconds 30
    $NewMailbox = Get-Mailbox -identity $MailboxAddress #Get the new mailbox
    New-MailboxRestoreRequest -SourceMailbox $mailbox.ExchangeGuid -TargetMailbox $NewMailbox.ExchangeGuid -AllowLegacyDNMismatch | Out-Null #Restore the mailbox 
 }

 $deletedmailboxes = Get-Mailbox -SoftDeletedMailbox -Archive #Get all Archive deleted mailboxes
 foreach ($mailbox in $deletedmailboxes)
 {
    $MailboxAddress = $mailbox.Alias + $MailDomain #Create mailbox address
    Write-Host "Restoring $MailboxAddress archive"
    $NewMailbox = Get-Mailbox -identity $MailboxAddress #Get the new mailbox
    New-MailboxRestoreRequest -SourceMailbox $mailbox.ExchangeGuid -SourceIsArchive -TargetMailbox $NewMailbox.ExchangeGuid -AllowLegacyDNMismatch | Out-Null #Restore the mailbox 
 }