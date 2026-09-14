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
$YamlJson = Get-Content -Raw $Settings | python -c "import sys,json,yaml; print(json.dumps(yaml.safe_load(sys.stdin.read()) or {}))"
$Config = $YamlJson | ConvertFrom-Json

$KeyPath = $Config.ssh_private_key_path
if ([string]::IsNullOrWhiteSpace($KeyPath)) { $KeyPath = '~/.ssh/oci-agent-vm_ed25519' }
if ($KeyPath.StartsWith('~/')) { $KeyPath = Join-Path $HOME $KeyPath.Substring(2) }
$KeyPath = [Environment]::ExpandEnvironmentVariables($KeyPath)

$PublicKey = [string]$Config.ssh_public_key
if ([string]::IsNullOrWhiteSpace($PublicKey)) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $KeyPath) | Out-Null
    if (-not (Test-Path $KeyPath)) {
        ssh-keygen -t ed25519 -f $KeyPath -N '' -C 'oci-agent-vm'
    }
    $PublicKey = (Get-Content "$KeyPath.pub" -Raw).Trim()
}

$Allowed = @(
    'region', 'oci_profile', 'tenancy_ocid', 'vcn_id', 'subnet_id',
    'instance_id', 'enable_provisioning', 'availability_domain',
    'compartment_ocid', 'ssh_public_key', 'instance_name',
    'instance_ocpus', 'instance_memory_gb', 'ssh_ingress_cidr', 'install_git'
)
$Tfvars = @{}
foreach ($Name in $Allowed) {
    $Property = $Config.PSObject.Properties[$Name]
    if ($null -ne $Property -and $null -ne $Property.Value) { $Tfvars[$Name] = $Property.Value }
}
$Tfvars['ssh_public_key'] = $PublicKey
$Tfvars | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $Generated

try {
    Push-Location $TerraformDir
    oci iam region-subscription list --profile ([string]$Config.oci_profile)
    terraform init
    terraform fmt -recursive
    terraform validate
    terraform plan
    terraform apply
} finally {
    Pop-Location
    Remove-Item -Force -ErrorAction SilentlyContinue $Generated
}
