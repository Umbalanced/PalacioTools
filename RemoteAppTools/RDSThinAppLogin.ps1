$OneDriveForBizFolderName = "OneDrive - Palacio Tech" #Name of the OneDrive for Business folder


$PinnedFolders = (((New-Object -ComObject Shell.Application).Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}").Items() | Where-Object IsFolder -eq $True).verbs()) 
#This line creates a COM object to interact with explorer, then gets the quick access folder, then gets the items in the folder, then filters out the items that are not folders, then gets the verbs for those folders, then filters out the verbs that are not pin to quick access
$PinnedFolders | Where-Object {$_.name -eq "Unpin from Quick Access"} | ForEach-Object { $_.DoIt() }
$PinnedFolders | Where-Object {$_.name -eq "Remove From Quick Access"} | ForEach-Object { $_.DoIt() }
#The lines above take the folders generated above and unpins the folders that are pinned to quick access

#This section adds local folders to quick access
$path = "\\Tsclient\c\Users\" + $env:UserName #concatinate the RDS file redirection path with the username
$Explorer = new-object -com shell.application #Create COM object to interact with explorer
$Explorer.Namespace($path).Self.InvokeVerb("pintohome") #Trigger the pin to quick access with righ-click verb

#Pin local downloads
$subpath = $Path + "\Downloads" #concatinate the path with the downloads folder
$Explorer.Namespace($subpath).Self.InvokeVerb("pintohome")

#Test if OneDrive installed and configured, if so use that path instead
if(Test-Path @($Path+"\$OneDriveForBizFolderName")){
    $Path = "$Path+$OneDriveForBizFolderName"
}
#Pin local desktop
$subpath = $path + "\Desktop" #concatinate the path with the desktop folder
$Explorer.Namespace($subpath).Self.InvokeVerb("pintohome")
#Pin local documents
$subpath = $Path + "\Documents" #concatinate the path with the documents folder
$Explorer.Namespace($subpath).Self.InvokeVerb("pintohome")
#Pin local downloads


#Add user folder as mapped drive
New-PSDrive -Name "U" -PSProvider FileSystem -Root $path -Persist
