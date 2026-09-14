variable "region" {
  description = "OCI region."
  type        = string
  default     = "ap-mumbai-1"
}

variable "oci_profile" {
  description = "Profile in ~/.oci/config used for read-only discovery."
  type        = string
  default     = "DEFAULT"
}

variable "tenancy_ocid" {
  description = "Tenancy OCID used to scope discovery."
  type        = string
  sensitive   = true
}

variable "vcn_id" {
  description = "Existing VCN OCID for read-only mode."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Existing subnet OCID for read-only mode."
  type        = string
  default     = ""
}

variable "instance_id" {
  description = "Existing instance OCID to inspect."
  type        = string
  default     = ""
}

variable "enable_provisioning" {
  description = "Create the tutorial VM/network. Set false for read-only discovery."
  type        = bool
  default     = true
}

variable "availability_domain" {
  description = "OCI availability domain for a new instance."
  type        = string
  default     = "BDKv:AP-MUMBAI-1-AD-1"
}

variable "compartment_ocid" {
  description = "Compartment for new resources; defaults to tenancy."
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key installed on a new VM."
  type        = string
  default     = ""
}

variable "instance_name" {
  type    = string
  default = "agent-vm"
}

variable "instance_ocpus" {
  type    = number
  default = 1
}

variable "instance_memory_gb" {
  type    = number
  default = 6
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to SSH to the new VM. Prefer your fixed public IP/32."
  type        = string
  default     = "0.0.0.0/0"
}

variable "install_git" {
  description = "Install Git in the VM image. Disable for a smaller VM when Git is not needed."
  type        = bool
  default     = true
}
