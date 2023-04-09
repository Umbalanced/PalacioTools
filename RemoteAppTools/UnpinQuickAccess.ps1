$PinnedFolders = (((New-Object -ComObject Shell.Application).Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}").Items() | Where-Object IsFolder -eq $True).verbs()) 
#This line creates a COM object to interact with explorer, then gets the quick access folder, then gets the items in the folder, then filters out the items that are not folders, then gets the verbs for those folders, then filters out the verbs that are not pin to quick access

$PinnedFolders | Where-Object {$_.name -eq "Unpin from Quick Access"} | ForEach-Object { $_.DoIt() }
$PinnedFolders | Where-Object {$_.name -eq "Remove From Quick Access"} | ForEach-Object { $_.DoIt() }
#These lines take the folders generated above and unpins the folders that are pinned to quick access