# Connect to the provisioned VM using the Terraform-managed public IP.
# LOCAL WORKSTATION ONLY.
[CmdletBinding()]
param(
    [switch]$PrintVncPassword,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$SshArguments
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TerraformDir = Join-Path $Root 'terraform'
$Settings = Join-Path $Root 'settings.yaml'

$PublicIp = (& terraform "-chdir=$TerraformDir" output -raw created_instance_public_ip 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($PublicIp) -or $PublicIp -eq 'null') {
    throw 'No VM public IP found. Run setup.ps1 successfully first.'
}

$KeyPath = '~/.ssh/oci-agent-vm_ed25519'
if (Test-Path $Settings -PathType Leaf) {
    $ConfiguredKeyPath = & python -c "import os,sys,yaml; print((yaml.safe_load(open(sys.argv[1])) or {}).get('ssh_private_key_path') or '')" $Settings
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ConfiguredKeyPath)) {
        $KeyPath = $ConfiguredKeyPath.Trim()
    }
}
if ($KeyPath.StartsWith('~/')) { $KeyPath = Join-Path $HOME $KeyPath.Substring(2) }
$KeyPath = [Environment]::ExpandEnvironmentVariables($KeyPath)
if (-not [System.IO.Path]::IsPathRooted($KeyPath)) { $KeyPath = Join-Path $Root $KeyPath }
if (-not (Test-Path $KeyPath -PathType Leaf)) {
    throw "SSH private key not found: $KeyPath"
}

$SshOptions = @('-i', $KeyPath, '-o', 'StrictHostKeyChecking=accept-new')
if ($PrintVncPassword) {
    & ssh @SshOptions "ubuntu@$PublicIp" 'cat ~/.config/remote-desktop/vnc-password.txt'
} else {
    & ssh @SshOptions "ubuntu@$PublicIp" @SshArguments
}
exit $LASTEXITCODE
