$DC = "Lab-util" #Name of the domain controller to query
$Domain = "Lab.local" #Name of the domain (Used to trim the domain name from the server name)

$Session = New-PSSession -ComputerName ROLL-DC-01
$servers = Invoke-Command -session $session -scriptblock {
    return (Get-ADComputer -Filter "OperatingSystem -Like '*Windows Server*'" -Properties OperatingSystem)
}
#Create arraylists to store the server names
$ServerList = [System.Collections.ArrayList]::new()
$DatacenterList = [System.Collections.ArrayList]::new()
$StandardList = [System.Collections.ArrayList]::new()
$NotMatchingList = [System.Collections.ArrayList]::new()
$NotMatchingList = [System.Collections.ArrayList]::new()
$SQLStandardList = [System.Collections.ArrayList]::new()
$ProbableCNAME = [System.Collections.ArrayList]::new()
#Test each server to see if it is pingable, if so add it to the arraylist
foreach ($server in $servers) {
    if ($(Test-NetConnection -computername $server.DNSHostName).PingSucceeded) {
        $ServerList.Add($server.Name)
    }
}
#From the pingable servers, get the OS version
$ServerObject = Invoke-Command -ArgumentList (, $ServerList) -Session $session -scriptblock {
    param(
        [System.Collections.ArrayList]$ServerList
    )
    $ServerObject = for ($i = 0; $i -lt $ServerList.Count; $i++) {
        $Computer = Get-ADComputer -Identity $ServerList[$i] -Properties OperatingSystem
        [PSCustomObject]@{
            Name            = $Computer.Name
            DNSHostName     = $Computer.DNSHostName
            OperatingSystem = $Computer.OperatingSystem
        }
    }
    return $ServerObject
}
#From the OS version, determine if it is a Datacenter or Standard server
foreach ($server in $ServerObject) {
    if ($server.OperatingSystem -like "*Datacenter*") {
        $DatacenterList.Add($server.Name)
    }
    elseif ($server.OperatingSystem -like "*Standard*") {
        $StandardList.Add($server.Name)
    }
    else {
        $NotMatchingList.Add($server.Name)
    }
}


#This block attempts to determine if there is an old computer object with an A record pointing to a different server. This is a common issue when a server is renamed and the old computer object is not deleted.  This block will attempt to determine if the server name is a CNAME and if so add it to the $ProbableCNAME arraylist
Foreach ($Server in $ServerObject) {
    $Session = New-PSSession -ComputerName $Server.DNSHostName
    $ComName = Invoke-Command -Session $Session -ArgumentList $Server -ScriptBlock {
        param(
            [PSCustomObject]$Server
        )
        $ServerName = $Server.DNSHostName.Trim($Domain)
        return $ENV:COMPUTERNAME
    }
    if ($ComName -like $Server.DNSHostName.trim($Domain)) {
        write-host "$($Server.DNSHostName) is a CNAME"
        $ProbableCNAME.Add(([string]$Server.Name))
    }
}


# Determine is SQL Standard is installed, if you have other SQL editions you want to search for copy this block and edit the -like "*Standard*" to match your edition aka:   if((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Edition -like "*Datacenter*")
foreach ($server in $ServerObject) {
     $Session = New-PSSession -ComputerName $server.DNSHostName 
     $HasSqlStandard = Invoke-command -session $Session -scriptblock {
        $inst = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances
        foreach ($i in $inst) {
            $p = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL').$i
            if((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Edition -like "*Standard*") {
                return $true
            }
        }
    }
    if ($HasSqlStandard) {
        $SQLStandardList.Add($server.Name)
    }
    $HasSqlStandard = $false
}
#Write the results to the console
Write-host "We have $($ServerList.Count) servers"
Write-host "We have $($DatacenterList.Count) Datacenter servers"
Write-host "We have $($StandardList.Count) Standard servers"
Write-host "We have $($ProbableCNAME.Count) servers that are probably just CNAMEs"
Write-host "We have $($NotMatchingList.Count) servers that do not match"
$NotMatchingList
Write-host "We have $($SQLStandardList.Count) servers with SQL Standard"
$SQLStandardList