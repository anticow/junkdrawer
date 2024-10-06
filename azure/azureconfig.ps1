[CmdletBinding()]
Param(
    [switch] $Force
)
# Start Region: Set user inputs

$location = 'eastus'

$applianceSubscriptionId = 'd8c01b16-9767-42f6-86ad-51ac2ad7071f'
$applianceResourceGroupName = 'jjbackupshome'
$applianceName = 'homearc'

$customLocationSubscriptionId = 'd8c01b16-9767-42f6-86ad-51ac2ad7071f'
$customLocationResourceGroupName = 'jjbackupshome'
$customLocationName = 'homearc'

$vCenterSubscriptionId = 'd8c01b16-9767-42f6-86ad-51ac2ad7071f'
$vCenterResourceGroupName = 'jjbackupshome'
$vCenterName = 'homevm'

# End Region: Set user inputs

function confirmationPrompt($msg) {
    Write-Host $msg
    while ($true) {
        $inp = Read-Host "Yes(y)/No(n)?"
        $inp = $inp.ToLower()
        if ($inp -eq 'y' -or $inp -eq 'yes') {
            return $true
        }
        elseif ($inp -eq 'n' -or $inp -eq 'no') {
            return $false
        }
    }
}

$logFile = "arcvmware-output.log"

function logH1($msg) {
    $pattern = '0-' * 40
    $spaces = ' ' * (40 - $msg.length / 2)
    $nl = [Environment]::NewLine
    $msgFull = "$nl $nl $pattern $nl $spaces $msg $nl $pattern $nl"
    Write-Host -ForegroundColor Green $msgFull
    Write-Output $msgFull >> $logFile
}

function logH2($msg) {
    $msgFull = "==> $msg"
    Write-Host -ForegroundColor Magenta $msgFull
    Write-Output $msgFull >> $logFile
}

function logText($msg) {
    Write-Host "$msg"
    Write-Output "$msg" >> $logFile
}

function createRG($subscriptionId, $rgName) {
    $group = (az group show --subscription $subscriptionId -n $rgName)
    if (!$group) {
        logText "Resource Group $rgName does not exist in subscription $subscriptionId. Trying to create the resource group"
        az group create --subscription $subscriptionId -l $location -n $rgName
    }
}


logH1 "Step 1/5: Setting up the current workstation"

if (!$UseProxy -and (confirmationPrompt -msg "Is the current workstation behind a proxy?")) {
    $UseProxy = $true
}

Write-Host "Setting the TLS Protocol for the current session to TLS 1.2."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$proxyCA = ""

if ($UseProxy) {
    logH2 "Provide proxy details"
    $proxyURL = Read-Host "Proxy URL"
    if ($proxyURL.StartsWith("http") -ne $true) {
        $proxyURL = "http://$proxyURL"
    }

    $noProxy = Read-Host "No Proxy (comma separated)"

    $env:http_proxy = $proxyURL
    $env:HTTP_PROXY = $proxyURL
    $env:https_proxy = $proxyURL
    $env:HTTPS_PROXY = $proxyURL
    $env:no_proxy = $noProxy
    $env:NO_PROXY = $noProxy

    $proxyCA = Read-Host "Proxy CA cert path (Press enter to skip)"
    if ($proxyCA -ne "") {
        $proxyCA = Resolve-Path -Path $proxyCA
    }

    $credential = $null
    $proxyAddr = $proxyURL

    if ($proxyURL.Contains("@")) {
        $x = $proxyURL.Split("//")
        $proto = $x[0]
        $x = $x[2].Split("@")
        $userPass = $x[0]
        $proxyAddr = $proto + "//" + $x[1]
        $x = $userPass.Split(":")
        $proxyUsername = $x[0]
        $proxyPassword = $x[1]
        $password = ConvertTo-SecureString -String $proxyPassword -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $proxyUsername, $password
    }

    [system.net.webrequest]::defaultwebproxy = new-object system.net.webproxy($proxyAddr)
    [system.net.webrequest]::defaultwebproxy.credentials = $credential
    [system.net.webrequest]::defaultwebproxy.BypassProxyOnLocal = $true
}

$forceApplianceRun = ""
if ($Force) { $forceApplianceRun = "--force" }

# Start Region: Create python virtual environment for azure cli

logH2 "Creating a temporary folder in the current directory (.temp)"
New-Item -Force -Path "." -Name ".temp" -ItemType "directory" > $null

$ProgressPreference = 'SilentlyContinue'

logH2 "Validating and installing 64-bit python"
try {
    $bitSize = py -c "import struct; print(struct.calcsize('P') * 8)"
    if ($bitSize -ne "64") {
        throw "Python is not 64-bit"
    }
    logText "64-bit python is already installed"
}
catch {
    logText "Installing python..."
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.8.8/python-3.8.8-amd64.exe" -OutFile ".temp/python-3.8.8-amd64.exe"
    $p = Start-Process .\.temp\python-3.8.8-amd64.exe -Wait -PassThru -ArgumentList '/quiet InstallAllUsers=0 PrependPath=1 Include_test=0'
    $exitCode = $p.ExitCode
    if ($exitCode -ne 0) {
        throw "Python installation failed with exit code $LASTEXITCODE"
    }
}
$ProgressPreference = 'Continue'

logText "Enabling long path support for python..."
Start-Process powershell.exe -verb runas -ArgumentList "Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled -Value 1" -Wait

py -m venv .temp\.env

logH2 "Installing azure cli."
logText "This might take a while..."
if ($proxyCA -ne "") {
    .temp\.env\Scripts\python.exe -m pip install --cert $proxyCA --upgrade pip wheel setuptools >> $logFile
    .temp\.env\Scripts\pip install --cert $proxyCA azure-cli >> $logFile
}
else {
    .temp\.env\Scripts\python.exe -m pip install --upgrade pip wheel setuptools >> $logFile
    .temp\.env\Scripts\pip install azure-cli >> $logFile
}

.temp\.env\Scripts\Activate.ps1

# End Region: Create python virtual environment for azure cli

try {
    if ($proxyCA -ne "") {
        $env:REQUESTS_CA_BUNDLE = $proxyCA
    }

    logH2 "Installing az cli extensions for Arc"
    az extension add --upgrade --name arcappliance
    az extension add --upgrade --name k8s-extension
    az extension add --upgrade --name customlocation
    az extension add --upgrade --name connectedvmware

    logH2 "Logging into azure"

    $azLoginMsg = "Please login to Azure CLI.`n" +
    "`t* If you're running the script for the first time, select yes.`n" +
    "`t* If you've recently logged in to az while running the script, you can select no.`n" +
    "Confirm login to azure cli?"
    if (confirmationPrompt -msg $azLoginMsg) {
        az login --use-device-code -o table
    }

    az account set -s $applianceSubscriptionId
    if ($LASTEXITCODE) {
        $Error[0] | Out-String >> $logFile
        throw "The default subscription for the az cli context could not be set."
    }

    logH1 "Step 1/5: Workstation was set up successfully"

    createRG "$applianceSubscriptionId" "$applianceResourceGroupName"

    logH1 "Step 2/5: Creating the Arc resource bridge"
    logH2 "Provide vCenter details to deploy Arc resource bridge VM. The credentials will be used by Arc resource bridge to update and scale itself."

    az arcappliance run vmware --debug --tags "" $forceApplianceRun --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name $applianceName --location $location

    $applianceId = (az arcappliance show --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name $applianceName --query id -o tsv 2>> $logFile)
    if (!$applianceId) {
        throw "Appliance creation has failed."
    }
    $applianceStatus = (az resource show --debug --ids "$applianceId" --query 'properties.status' -o tsv 2>> $logFile)
    if ($applianceStatus -ne "Running") {
        throw "Appliance is not in running state. Current state: $applianceStatus."
    }

    logH1 "Step 2/5: Arc resource bridge is up and running"
    logH1 "Step 3/5: Installing cluster extension"

    az k8s-extension create --debug --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name azure-vmwareoperator --extension-type 'Microsoft.vmware' --scope cluster --cluster-type appliances --cluster-name $applianceName --config Microsoft.CustomLocation.ServiceAccount=azure-vmwareoperator 2>> $logFile

    $clusterExtensionId = (az k8s-extension show --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name azure-vmwareoperator --cluster-type appliances --cluster-name $applianceName --query id -o tsv 2>> $logFile)
    if (!$clusterExtensionId) {
        throw "Cluster extension installation failed."
    }
    $clusterExtensionState = (az resource show --debug --ids "$clusterExtensionId" --query 'properties.provisioningState' -o tsv 2>> $logFile)
    if ($clusterExtensionState -ne "Succeeded") {
        throw "Provisioning State of cluster extension is not succeeded. Current state: $clusterExtensionState."
    }

    logH1 "Step 3/5: Cluster extension installed successfully"
    logH1 "Step 4/5: Creating custom location"

    createRG "$customLocationSubscriptionId" "$customLocationResourceGroupName"

    $customLocationNamespace = ("$customLocationName".ToLower() -replace '[^a-z0-9-]', '')
    az customlocation create --debug --tags "" --subscription $customLocationSubscriptionId --resource-group $customLocationResourceGroupName --name $customLocationName --location $location --namespace $customLocationNamespace --host-resource-id $applianceId --cluster-extension-ids $clusterExtensionId 2>> $logFile

    $customLocationId = (az customlocation show --subscription $customLocationSubscriptionId --resource-group $customLocationResourceGroupName --name $customLocationName --query id -o tsv 2>> $logFile)
    if (!$customLocationId) {
        throw "Custom location creation failed."
    }
    $customLocationState = (az resource show --debug --ids $customLocationId --query 'properties.provisioningState' -o tsv 2>> $logFile)
    if ($customLocationState -ne "Succeeded") {
        throw "Provisioning State of custom location is not succeeded. Current state: $customLocationState."
    }

    logH1 "Step 4/5: Custom location created successfully"
    logH1 "Step 5/5: Connecting to vCenter"

    createRG "$vCenterSubscriptionId" "$vCenterResourceGroupName"

    logH2 "Provide vCenter details"
    logText "`t* These credentials will be used when you perform vCenter operations through Azure."
    logText "`t* You can provide the same credentials that you provided for Arc resource bridge earlier."

    az connectedvmware vcenter connect --debug --tags "" --subscription $vCenterSubscriptionId --resource-group $vCenterResourceGroupName --name $vCenterName --custom-location $customLocationId --location $location --port 443

    $vcenterId = (az connectedvmware vcenter show --subscription $vCenterSubscriptionId --resource-group $vCenterResourceGroupName --name $vCenterName --query id -o tsv 2>> $logFile)
    if (!$vcenterId) {
        throw "Connect vCenter failed."
    }
    $vcenterState = (az resource show --debug --ids "$vcenterId" --query 'properties.provisioningState' -o tsv 2>> $logFile)
    if ($vcenterState -ne "Succeeded") {
        throw "Provisioning State of vCenter is not succeeded. Current state: $vcenterState."
    }

    logH1 "Step 5/5: vCenter was connected successfully"
    logH1 "Your vCenter has been successfully onboarded to Azure Arc!"
}
catch {
    $err = $_.Exception | Out-String
    logText -ForegroundColor Red ("Script execution failed: " + $err)
}
finally {
    deactivate
}
