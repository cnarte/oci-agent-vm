# LOCAL WINDOWS WORKSTATION ONLY.
# VM bootstrap is bootstrap/cloud-init.yaml and runs inside the Linux VM.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TerraformDir = Join-Path $Root 'terraform'
$Settings = if ($env:SETTINGS_FILE) { $env:SETTINGS_FILE } else { Join-Path $Root 'settings.yaml' }
$Generated = Join-Path $TerraformDir 'settings.auto.tfvars.json'

function Require-Command($Name, $InstallUrl) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required. Install it from $InstallUrl"
    }
}

Require-Command 'terraform' 'https://developer.hashicorp.com/terraform/install'
Require-Command 'oci' 'https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm'
Require-Command 'ssh' 'https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse'
Require-Command 'ssh-keygen' 'https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse'
Require-Command 'python' 'https://www.python.org/downloads/windows/'

if (-not (Test-Path $Settings)) {
    throw "Missing $Settings. Copy settings.yaml.example to settings.yaml first."
}

# PyYAML is the only local YAML dependency; Terraform consumes the generated JSON file.
python -c "import yaml" 2>$null
if ($LASTEXITCODE -ne 0) { throw 'PyYAML is required. Install it with: python -m pip install --user pyyaml' }
$YamlJson = Get-Content -Raw $Settings | python -c "import sys,json,yaml; print(json.dumps(yaml.safe_load(sys.stdin.read()) or {}))"
$Config = $YamlJson | ConvertFrom-Json
$OciProfile = [string]$Config.oci_profile
if ([string]::IsNullOrWhiteSpace($OciProfile)) { $OciProfile = 'DEFAULT' }
& oci iam region-subscription list --profile $OciProfile *> $null
if ($LASTEXITCODE -ne 0) {
    throw "OCI CLI authentication failed for profile '$OciProfile'. Configure or log in to OCI before running setup.ps1."
}
$TenancyOcid = [string]$Config.tenancy_ocid
if ($TenancyOcid -match 'REPLACE|YOUR_TENANCY') { $TenancyOcid = '' }
if ([string]::IsNullOrWhiteSpace($TenancyOcid)) {
    $OciConfigPath = if ($env:OCI_CLI_CONFIG_FILE) { $env:OCI_CLI_CONFIG_FILE } else { Join-Path $HOME '.oci\config' }
    if (-not (Test-Path $OciConfigPath -PathType Leaf)) {
        throw "OCI config file not found: $OciConfigPath"
    }
    $InProfile = $false
    foreach ($Line in Get-Content $OciConfigPath) {
        if ($Line -match '^\s*\[([^\]]+)\]\s*$') {
            $InProfile = $Matches[1] -eq $OciProfile
            continue
        }
        if ($InProfile -and $Line -match '^\s*tenancy\s*=\s*([^#\s]+)') {
            $TenancyOcid = $Matches[1]
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($TenancyOcid)) {
        throw "OCI profile '$OciProfile' has no tenancy OCID. Set tenancy_ocid in settings.yaml to override it."
    }
}
$EnableProvisioning = $Config.enable_provisioning
if ($null -eq $EnableProvisioning) { $EnableProvisioning = $true }

$KeyPath = $Config.ssh_private_key_path
if ([string]::IsNullOrWhiteSpace($KeyPath)) { $KeyPath = '~/.ssh/oci-agent-vm_ed25519' }
if ($KeyPath.StartsWith('~/')) { $KeyPath = Join-Path $HOME $KeyPath.Substring(2) }
$KeyPath = [Environment]::ExpandEnvironmentVariables($KeyPath)
if (-not [System.IO.Path]::IsPathRooted($KeyPath)) { $KeyPath = Join-Path $Root $KeyPath }

$PublicKey = [string]$Config.ssh_public_key
if ([string]::IsNullOrWhiteSpace($PublicKey)) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $KeyPath) | Out-Null
    if (-not (Test-Path $KeyPath)) {
        # PowerShell 5 drops an empty native argument, so pipe two blank passphrases
        # instead of passing ssh-keygen's -N '' option.
        @('', '') | & ssh-keygen -t ed25519 -f $KeyPath -C 'oci-agent-vm'
        if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed while creating $KeyPath" }
    }
    $PublicKey = (Get-Content "$KeyPath.pub" -Raw).Trim()
} elseif (-not (Test-Path $KeyPath -PathType Leaf)) {
    throw "ssh_private_key_path is required when ssh_public_key is supplied: $KeyPath"
}

$Allowed = @(
    'region', 'oci_profile', 'tenancy_ocid', 'vcn_id', 'subnet_id',
    'instance_id', 'enable_provisioning', 'availability_domain', 'fault_domain',
    'compartment_ocid', 'ssh_public_key', 'instance_name',
    'instance_ocpus', 'instance_memory_gb', 'ssh_ingress_cidr', 'install_git'
)
$Tfvars = @{}
foreach ($Name in $Allowed) {
    $Property = $Config.PSObject.Properties[$Name]
    if ($null -ne $Property -and $null -ne $Property.Value) { $Tfvars[$Name] = $Property.Value }
}
$Tfvars['ssh_public_key'] = $PublicKey
$Tfvars['tenancy_ocid'] = $TenancyOcid
$Json = $Tfvars | ConvertTo-Json -Depth 10
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Generated, $Json, $Utf8NoBom)

try {
    Push-Location $TerraformDir
    terraform init
    terraform fmt -recursive
    terraform validate
    terraform plan
    if (-not [bool]$EnableProvisioning) {
        Write-Host 'Provisioning disabled; plan completed without applying changes.'
        return
    }
    terraform apply
    $PublicIp = terraform output -raw created_instance_public_ip 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($PublicIp) -and $PublicIp -ne 'null') {
        $PublicIp = $PublicIp.Trim()
        Write-Host "`nVM public IP: $PublicIp"
        Write-Host "SSH command: ssh -i `"$KeyPath`" ubuntu@$PublicIp"

        $VncSshArgs = @('-i', $KeyPath, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')
        Write-Host 'Waiting for SSH/cloud-init before retrieving the VNC password...'
        $PreviousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $VncSshReady = $false
            for ($Attempt = 1; $Attempt -le 30; $Attempt++) {
                & ssh @VncSshArgs "ubuntu@$PublicIp" 'true' *> $null
                if ($LASTEXITCODE -eq 0) { $VncSshReady = $true; break }
                Start-Sleep -Seconds 10
            }
            if ($VncSshReady) {
                & ssh @VncSshArgs "ubuntu@$PublicIp" 'timeout 900 cloud-init status --wait' *> $null
                if ($LASTEXITCODE -eq 0) {
                    $VncPassword = ((& ssh @VncSshArgs "ubuntu@$PublicIp" 'cat ~/.config/remote-desktop/vnc-password.txt' 2>$null) | Out-String).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($VncPassword)) {
                        Write-Host "VNC password: $VncPassword"
                        Write-Host 'VNC password file: ~/.config/remote-desktop/vnc-password.txt'
                        Write-Warning 'Treat the VNC password as a secret; do not commit or share it.'
                    } else {
                        Write-Warning 'VNC password was not available; retrieve it over SSH after cloud-init completes.'
                    }
                } else {
                    Write-Warning 'Cloud-init was not ready; VNC password was not retrieved.'
                }
            } else {
                Write-Warning 'SSH was not ready; VNC password was not retrieved.'
            }
        } finally {
            $ErrorActionPreference = $PreviousErrorActionPreference
        }

        $Telegram = $null
        $TelegramProperty = $Config.PSObject.Properties['telegram']
        if ($null -ne $TelegramProperty) { $Telegram = $TelegramProperty.Value }
        $HermesToken = if ($null -ne $Telegram) { [string]$Telegram.hermes_bot_token } else { '' }
        $CcToken = if ($null -ne $Telegram) { [string]$Telegram.cc_connect_bot_token } else { '' }
        $Users = if ($null -ne $Telegram) { @($Telegram.allowed_users | ForEach-Object { [string]$_ }) } else { @() }
        $TelegramPayload = $null
        if (-not [string]::IsNullOrWhiteSpace($HermesToken) -or -not [string]::IsNullOrWhiteSpace($CcToken)) {
            if ($Users.Count -eq 0 -or @($Users | Where-Object { $_ -notmatch '^[0-9]+$' }).Count -gt 0) {
                Write-Warning 'Telegram tokens supplied but allowed_users is empty or invalid; Telegram setup skipped.'
            } elseif (($HermesToken -and $HermesToken -notmatch '^[0-9]+:[A-Za-z0-9_-]+$') -or
                      ($CcToken -and $CcToken -notmatch '^[0-9]+:[A-Za-z0-9_-]+$')) {
                Write-Warning 'Telegram token format is invalid; Telegram setup skipped.'
            } else {
                $TelegramPayload = @{
                    hermes_bot_token = $HermesToken
                    cc_connect_bot_token = $CcToken
                    allowed_users = $Users
                } | ConvertTo-Json -Compress
            }
        }
        if ($null -ne $TelegramPayload -and (Test-Path $KeyPath)) {
            $SshArgs = @('-i', $KeyPath, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')
            Write-Host 'Waiting for SSH/cloud-init before configuring Telegram...'
            # A failed native ssh command is a normal retry condition. PowerShell's
            # Stop preference otherwise turns its stderr into a terminating error.
            $PreviousErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $SshReady = $false
                for ($Attempt = 1; $Attempt -le 30; $Attempt++) {
                    & ssh @SshArgs "ubuntu@$PublicIp" 'true' *> $null
                    if ($LASTEXITCODE -eq 0) { $SshReady = $true; break }
                    Start-Sleep -Seconds 10
                }
                if ($SshReady) {
                    & ssh @SshArgs "ubuntu@$PublicIp" 'timeout 900 cloud-init status --wait' *> $null
                    if ($LASTEXITCODE -eq 0) {
                        $TelegramPayload | & ssh @SshArgs "ubuntu@$PublicIp" 'python3 /usr/local/sbin/configure-agent-telegram.py' *> $null
                        if ($LASTEXITCODE -ne 0) { Write-Warning 'Automatic Telegram setup failed; configure it manually on the VM.' }
                    } else {
                        Write-Warning 'cloud-init did not finish; Telegram setup was not attempted.'
                    }
                } else {
                    Write-Warning 'SSH was not ready; Telegram setup was not attempted.'
                }
            } finally {
                $ErrorActionPreference = $PreviousErrorActionPreference
            }
        }
    }
} finally {
    Pop-Location
    Remove-Item -Force -ErrorAction SilentlyContinue $Generated
}
