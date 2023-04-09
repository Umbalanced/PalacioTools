$DC = "Lab-util" #Name of the domain controller to query

$CurrentUserDocsPath = [Environment]::GetFolderPath("MyDocuments")


$Session = New-PSSession -ComputerName $DC
$servers = Invoke-Command -session $session -scriptblock{
    return (Get-ADComputer -Filter "OperatingSystem -Like '*Windows Server*'")
}
$DeadServerList = [System.Collections.ArrayList]::new()

foreach($server in $servers){
    if(!($(Test-NetConnection -computername $server.DNSHostName).PingSucceeded))
    {
        $DeadServerList.Add($server.Name)
    }
}

Export-Csv -inputobject $DeadServerList -path "$CurrentUserDocsPath\DeadServerList.csv"