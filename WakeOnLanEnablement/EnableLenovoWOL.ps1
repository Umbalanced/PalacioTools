$getLenovoBIOS = gwmi -class Lenovo_SetBiosSetting -namespace root\wmi
$getLenovoBIOS.SetBiosSetting("WakeOnLAN,ACOnly")
$SaveLenovoBIOS = (gwmi -class Lenovo_SaveBiosSettings -namespace root\wmi)
$SaveLenovoBIOS.SaveBiosSettings()
$getLenovoBIOS = gwmi -class Lenovo_SetBiosSetting -namespace root\wmi
$getLenovoBIOS.SetBiosSetting("WakeOnLANDock,Enable")
$SaveLenovoBIOS = (gwmi -class Lenovo_SaveBiosSettings -namespace root\wmi)
$SaveLenovoBIOS.SaveBiosSettings()