Param($name,$ipaddress,$server,$zone,$recordtype)
$resource = Get-DnsServerResourceRecord -name $name -zonename $zone -ErrorAction SilentlyContinue
if ($resource) {

    $newresource = $resource.clone()
    $newresource.recorddata.IPv4Address = $ipaddress.tostring()
    Set-DnsServerResourceRecord -NewInputObject $newresource -OldInputObject $resource -ZoneName $zone
}
else {
if ($recordtype -eq "CNAME") {
    Add-DnsServerResourceRecordcname  -Name $name -IPv4Address $ipaddress -TimeToLive 300 -ZoneName $zone 
}
elseif ($recordtype -eq "TXT"){}
else {
Add-DnsServerResourceRecordA  -Name $name -IPv4Address $ipaddress -TimeToLive 300 -ZoneName $zone 
}

}
