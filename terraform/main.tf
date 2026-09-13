# Existing-resource inventory. Set enable_provisioning=false when using only these data sources.

data "oci_identity_tenancy" "current" {
  tenancy_id = var.tenancy_ocid
}

data "oci_core_vcn" "existing" {
  count  = var.vcn_id == "" ? 0 : 1
  vcn_id = var.vcn_id
}

data "oci_core_subnet" "existing" {
  count     = var.subnet_id == "" ? 0 : 1
  subnet_id = var.subnet_id
}

data "oci_core_instance" "existing" {
  count       = var.instance_id == "" ? 0 : 1
  instance_id = var.instance_id
}

data "oci_core_vnic_attachments" "instance" {
  count               = var.instance_id == "" ? 0 : 1
  compartment_id      = var.tenancy_ocid
  instance_id         = var.instance_id
  availability_domain = data.oci_core_instance.existing[0].availability_domain
}
