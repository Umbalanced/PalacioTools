$path = "\\Tsclient\c\Users\" + $env:UserName
New-PSDrive -Name "U" -PSProvider FileSystem -Root $path -Persist