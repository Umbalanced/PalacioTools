##This script is mass deploying large installers via BITS and 7Zip
##Written by Michael Palacio, michael@palaciotech.io 2023


#####Overall flags
$IsDeploying = $true #Activiate mass deployment mode, this checks if it can ping the deployment web-host before starting, and if it can't holds off for an hour before trying again.
$PromptUser = $False #Prompt the user to save work before deployment. This will throw up a message box and wait 10 minutes before killing processes and starting the install
$ShowDownloadProgress = $true

#####Bits Setup
$BitsJobName = "DeployAutocad"
$BitsServerHostname = "Lab-util.lab.local" 
###If you want to set up multiple bits servers, you can use this command to get the AD Site the device is in and use a series of ifs or a switch statement to selecct the correct server
###(Get-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters).DynamicSiteName
$BitsPath = "AutoCadDeployment/2023" 
$ZippedFileName = "Autocad.7z"
$RemoteHTTPSPath = "https://$BitsServerHostname/$BitsPath/$ZippedFileName" #Construct the path to the file we're going to download
$ZippedFileHash = '' #If you want to check the hash of the file you're downloading, put it here. If you don't, leave it blank. This script uses this to determine if a previously downloaded version of a file

#####Local File Setup
$BasePath = "C:\Installers" #Leave blank if you want to place the zipped files and extracted files in different locations

$ZipDownloadFolder = "\7Zip"#Leave blank if you want to place the zipped files in the base folder

$ExtractPath = "\Autocad" #Leave blank if you want to place the zipped files in the base folder, if you're zipping a folder, you'll want to leave this blank

$ExtractPath = "$BasePath + $ExtractPath" #Construct the path to the folder we're going to extract to

$ZipDownloadFolder = $BasePath + $ZipDownloadFolder #Construct the path to the folder we're going to download the zipped file to

$InstallerPath = "C:\Autocad\Setup.exe" #Full path to the installer you want to run
#If you want to pass arguments to the installer, put them here between the @'s. The @'s are required to allow for multi-line strings
$InstallerArguments = @"
/s /v/qn" 
"@


#####SQL Logging Setup
$UseSQLLogging = $True #Allows you to log install info to a SQL Server
$SQLServerHostname = "Lab-MS-SQL.lab.local"
$SQLUserName = 'DeployInventorVault'
$SQLPassword = 'gO*HAbbu4hqEdSvRnuR!7TBM93boJe' #If you use this method, you *must* use SQL authentication and give the accounts only insert, select and update rights to the target table. I generally run this as NT\SYSTEM so this is marginally better than using anonymous auth
$SQLPassword = ConvertTo-SecureString -String $SQLPassword -AsPlainText -Force
$cred = new-object System.Management.Automation.PSCredential -argumentlist $SQLUserName, $SQLPassword #Cast to a credential to be used with the SQL cmdlet



[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 #Force TLS 1.2
$IsDownloaded = $false #Set the downloaded variable to false
$ProgressPreference = "SilentlyContinue" #Hide progress bars

if ($UseSQLLogging) {
    try {
        #Try to import SQLServer module, if not install it
        Import-Module -Name SQLServer -ErrorAction Stop
    }
    catch {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force #Installs NuGet so that the module can install
        Install-Module -Name SQLServer -Force -confirm:$False #Installs the module
        Import-Module -Name SQLServer -ErrorAction Stop #Import the update module
    }
}


If ($IsDeploying) {
    #Checks to see if we can reach the web server, if not we wait an hour. After 24 hours we give up and exit
    $HoursWaited = 0
    while (!($(Test-NetConnection -computername $BitsServerHostname).PingSucceeded)) {
        Write-Host "No connection, waiting for an hour"
        Start-Sleep -seconds 3600
        if ($HoursWaited -ge 24) {
            #If we've waited for over 24 hours, give up
            Throw "Cannot connect to file server, exiting"
        }
        else {
            $HoursWaited++
        }
    }
}
if ($UseSQLLogging) {
    start-sleep -milliseconds (Get-Random -Minimum 1 -Maximum 30000) #Sleep for a random amount of time to avoid collisions with transaction IDs in the SQL database. If you are more clever than me there is probably a way to increment this in one transaction and then return the transaction ID so you can take advantage of SQL locking
    $TransactionID = Invoke-Sqlcmd -Credential $cred -ServerInstance $SQLServerHostname -Query "SELECT MAX(TransactionId) FROM dbo.Inventor2023Deployment" #Gets the last transaction ID
    if ("" -eq $TransactionID.Column1) {
        #If there is no transaction ID, set it to 1
        $TransactionID = 1
    }
    else {
        $TransactionID = $TransactionID.Column1 + 1 #Increments the transaction ID, drops the data type down to just an integer
    }
    #Insert initial log, capturing the transaction ID 
    Invoke-Sqlcmd -Credential $cred -ServerInstance $SQLServerHostname -Query @"
    INSERT INTO dbo.Inventor2023Deployment (Hostname, Date, Time, TransactionId, Package)
    Values ('$env:computername','$(Get-Date -Format "MM/dd/yyyy")','$(Get-Date -Format "HH:mm:ss")', '$TransactionID','$BitsJobName')
"@    
}


Clear-Host
write-host "`n`n`n`n`n`n`n`n`n" #Get clear of the stupid Test-Net Connection progress bar that refuses to go away
Write-Host "Network connection established, starting download"

try {    
    try {
        Get-BitsTransfer | Where-Object { $_.DisplayName -eq "$BitsJobName" } | Complete-BitsTransfer -ErrorAction SilentlyContinue | Out-Null #If there is a BITS transfer in progress, try to complete it
    }
    catch {
        Get-BitsTransfer | Where-Object { $_.DisplayName -eq "$BitsJobName" } | Remove-BitsTransfer -ErrorAction SilentlyContinue | Out-Null #If we can't complete it, cancel it
    }
    try {
        Import-Module -Name 7Zip4Powershell -ErrorAction Stop #Try to import 7Zip module, if not install it
    }
    catch {
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force #Installs NuGet so that the module can install
            Install-Module -Name 7Zip4Powershell -Force -confirm:$False #Installs the module
            Import-Module -Name 7Zip4Powershell -ErrorAction Stop #Import the update module            
        }
        catch {
            Throw "Cannot load 7Zip module, exiting"
        }
    }
    ###This section tests for the existance of the directories we're going to expand into, if they exist we delete the contents 
    if (-not (test-path -path $ZipDownloadFolder)) {
        New-item -path $ZipDownloadFolder -ItemType Directory | Out-Null
    }
    elseif (Test-path "$ZipDownloadFolder\$ZippedFileName") {
        if ($(Get-FileHash -Path "$ZipDownloadFolder\$ZippedFileName").hash -eq $ZippedFileHash) {
            $IsDownloaded = $true
        }
    } 
    else {
        try {
            Remove-Item "$ZipDownloadFolder" -Recurse #If the directory does exist, but doesn't have a file with the correct hash, delete the file contents
        }
        catch {
            throw #If we can't get the directory structure right, throw an exception to the larger try catch block for logging
        }
        New-item -path $ZipDownloadFolder -ItemType Directory | Out-Null
    }

    if ((test-path -path "$ExtractPath")) {
        Remove-Item "$ExtractPath" -Recurse
    }
    
    if ($IsDownloaded -eq $false) {
        try {
            Start-BitsTransfer -Priority Normal -Source "$RemoteHTTPSPath" -Destination "$ZipDownloadFolder\$ZippedFileName" -TransferType Download -DisplayName "$BitsJobName" -Asynchronous | Out-Null    
        }
        catch {
            Write-Host "Error starting bits job `n`n"
            Write-Host $Error 
        }
        if ($UseSQLLogging) {
            Invoke-Sqlcmd -Credential $cred -ServerInstance $SQLServerHostname -Query @"
        UPDATE dbo.Inventor2023Deployment 
        SET DownloadStarted = 'True', Date = '$(Get-Date -Format "MM/dd/yyyy")', Time = '$(Get-Date -Format "HH:mm:ss")'
        WHERE TransactionId = $TransactionID
"@
        }
        #This while loop handles waiting for the Bits transfers to finish
        while (!(($(Get-BitsTransfer | Where-Object { $_.DisplayName -eq "$BitsJobName" }).JobState -eq "Transferred"))) {
            #If the Bits job is in an error state, exit
            if ($(Get-BitsTransfer | Where-Object { $_.DisplayName -eq "$BitsJobName" }).JobState -eq "Error") {
                Throw "Error downloading files, exiting"
            } #If the bits job failed to start in a way we didn't catch, exit
            if ($null -eq $(Get-BitsTransfer)) {
                Throw "Error downloading files, exiting"
            }
            if ($ShowDownloadProgress) {
                if ($(Get-BitsTransfer | Where-Object { $_.DisplayName -eq "$BitsJobName" }).JobState -eq "Transferring") {
                    #These code blocks run bitsadmin to get the current progress and display it as a percentage
                    $BitsString = -split $(bitsadmin /info $BitsJobName /verbose) #Run bitsadmin and then split the coresponding string into an array with the -split verb
                    $BitsIndex = [array]::indexof($BitsString, "BYTES:") #Find the index of the string "BYTES:" in the array, since this precedes the bytes downloaded and total bytes
                    $Numerator = [double]$BitsString[$BitsIndex + 1] #The numerator is the next index in the array, force cast this to a double so we can do division
                    $Denominator = [double]$BitsString[$BitsIndex + 3] #The denominator skips one, which is just a /, and then adds the next value to the variable. We then force cast it to a double
                    $Percent = ($Numerator / $Denominator * 100) #Do the math
                    $Percent = [math]::Round($Percent, 0) #Use the math namespace to round the number to the nearest whole number
                    Write-Host "$BitsJobName download is $Percent% complete"
                }
            }
            Start-Sleep -Seconds 10 #Check the status of the bits job every 10 seconds
        }
        Get-BitsTransfer | Where-Object { $_.DisplayName -eq "$BitsJobName" } | Complete-BitsTransfer | Out-Null #Complete the bits job
    }
    else {
        Write-host "Files already downloaded, skipping download"
    }
    if ($UseSQLLogging) {
        #Update SQL DB
        Invoke-Sqlcmd -Credential $cred -ServerInstance $SQLServerHostname -Query @"
        UPDATE dbo.Inventor2023Deployment 
        SET DownloadSuccessful = 'True', Date = '$(Get-Date -Format "MM/dd/yyyy")', Time = '$(Get-Date -Format "HH:mm:ss")'
        WHERE TransactionId = $TransactionID
"@    
    }
    Write-host "Downloads complete, starting extraction"
    Set-Location $ZipDownloadFolder
    Expand-7Zip -ArchiveFileName $ZippedFileName -TargetPath $ExtractPath
    Write-host "Extraction complete, starting installation"
    if ($UseSQLLogging) {
        #Update SQL DB
        Invoke-Sqlcmd -Credential $cred -ServerInstance $SQLServerHostname -Query @"
        UPDATE dbo.Inventor2023Deployment 
        SET ExtractionComplete = 'True', Date = '$(Get-Date -Format "MM/dd/yyyy")', Time = '$(Get-Date -Format "HH:mm:ss")'
        WHERE TransactionId = $TransactionID
"@
    }

    Write-Host "Killing Inventor and Vault processes"
    
    if ($PromptUser) {
        #Send message to user to save their work before the install begins
        $Message = "An update to AutoCad is about to install. Please save your work and close Inventor and Vault. The update will run in 10 minutes and will force-close the applications at that time"
        Invoke-WmiMethod -Path Win32_Process -Name Create -ArgumentList "msg * $Message" -ComputerName "localhost"
        Start-Sleep -Seconds 600 #Wait 10 minutes before continuing
    }

    #This section kills all the running Autodesk processes so we can install Inventor and Vault
    $Process = Get-Process
    if ($Process.ProcessName.Contains("dwgviewr")) {
        $Process | Where-Object { $_.ProcessName -eq "dwgviewr" } | Stop-Process -Force #Kills DWG Viewer
    }
    if ($Process.ProcessName.Contains("Connectivity.VaultPro")) { 
        $Process | Where-Object { $_.ProcessName -eq "Connectivity.VaultPro" } | Stop-Process -Force #Kills Vault Pro
    }
    if ($Process.ProcessName.Contains("acad")) {
        $Process | Where-Object { $_.ProcessName -eq "acad" } | Stop-Process -Force #Kills AutoCad
    }
    if ($Process.ProcessName.Contains("Inventor")) {
        $Process | Where-Object { $_.ProcessName -eq "Inventor" } | Stop-Process -Force #Kills Inventor
    }
    if ($UseSQLLogging) {
        #Update SQL DB
        Invoke-Sqlcmd -Credential $cred -ServerInstance $SQLServerHostname -Query @"
        UPDATE dbo.Inventor2023Deployment 
        SET ProcessesKilled = 'True', Date = '$(Get-Date -Format "MM/dd/yyyy")', Time = '$(Get-Date -Format "HH:mm:ss")'
        WHERE TransactionId = $TransactionID
"@
    }
    #Installs Software
    Start-Process -FilePath $InstallerPath -wait -PassThru -ArgumentList $InstallerArguments
    #If the installer doesn't properly exit with an exit code you may need to test if the software installed via WMI or some other method

    if ($UseSQLLogging) {
        #Update SQL DB
        Invoke-Sqlcmd -Credential $cred -ServerInstance $SQLServerHostname -Query @"
    UPDATE dbo.Inventor2023Deployment 
    SET InstallSuccessful = 'True', Date = '$(Get-Date -Format "MM/dd/yyyy")', Time = '$(Get-Date -Format "HH:mm:ss")'
    WHERE TransactionId = $TransactionID
"@
    }
    write-host "Install complete"
}
catch {
    Write-host "Failed `n`n"
    $Error | Write-Host
    if ($BasePath -eq "") {
        $Error | Out-File "$Error.txt"
    }
    else {
        $Error | Out-File "$BasePath\Error.txt"
    }
}
#Clean up all the loose files we don't need
$ErrorActionPreference = "SilentlyContinue"
Remove-Item $ExtractPath -Recurse 

