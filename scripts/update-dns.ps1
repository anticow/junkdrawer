Param ( [bool]$run = $false)
[string]$currIP = (Invoke-WebRequest http://ifconfig.me/ip  -usebasicparsing).content.Replace("`n","")
if ($currIP) {
$azureside = (Resolve-DnsName boundary.cowgomu.net -Type ANY -Server 8.8.8.8).ipaddress


$secpasswd = ConvertTo-SecureString -AsPlainText -Force <pw>
$pscredential = New-Object System.Management.Automation.PSCredential (<useridentity>, $secpasswd)
$mycreds = New-Object System.Management.Automation.PSCredential(<appid>, $secpasswd)
$TenantId = <TenantId>
$Subscription = <SubId>
$ZoneName = <ZoneName>
$ResourceGroup = <resourceGroup>

Login-AzureRmAccount -ServicePrincipal -Credential $mycreds -TenantId $TenantId -Subscription $Subscription

Get-AzureRmSubscription


$dnslist = get-azurermdnsrecordset -ZoneName $ZoneName -ResourceGroupName $ResourceGroup -RecordType A 

if ( $azureside -ne $currIP -or $run -eq $true) {

    foreach ($r in $dnslist) {
        $r.Records[0].Ipv4Address = $currIP
        Set-AzureRmDnsRecordSet -RecordSet $r
           
    }


}

$z = $ZoneName
$rg = $ResourceGroup
#$dnslist = get-azurermdnsrecordset -ZoneName $z -ResourceGroupName $rg

foreach ($d in $dnslist) {
    if ($d.name -eq "@" -or $d.name -eq "impediment" -or $d.name -eq "oculus" -or $d.name -eq "boundary.$ZoneName"`
        -or $d.name -eq "boundary" -or $d.name -eq "oculus.$ZoneName" -or $d.name -eq "impediment.$ZoneName"`
        -or $d.name -eq "home.$ZoneName" -or $d.name -eq "home") {
        write-output "$($d.name) is bad"
        }
        else { write-output "$($d.name) is proper" 
            .\update-localdns.ps1 -name $d.name -zone $z -ipaddress $d.records[0].Ipv4Address -recordtype $d.recordtype
        }
    }

}
else { write-output "failed to get external IP"}