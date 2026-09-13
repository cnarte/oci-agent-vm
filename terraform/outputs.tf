output "tenancy" {
  value = {
    name        = data.oci_identity_tenancy.current.name
    home_region = data.oci_identity_tenancy.current.home_region_key
  }
}

output "vcn" {
  value = var.vcn_id == "" ? null : {
    id         = data.oci_core_vcn.existing[0].id
    name       = data.oci_core_vcn.existing[0].display_name
    cidr_block = data.oci_core_vcn.existing[0].cidr_block
  }
}

output "subnet" {
  value = var.subnet_id == "" ? null : {
    id         = data.oci_core_subnet.existing[0].id
    name       = data.oci_core_subnet.existing[0].display_name
    cidr_block = data.oci_core_subnet.existing[0].cidr_block
    vcn_id     = data.oci_core_subnet.existing[0].vcn_id
  }
}

output "instance" {
  value = var.instance_id == "" ? null : {
    id                  = data.oci_core_instance.existing[0].id
    name                = data.oci_core_instance.existing[0].display_name
    shape               = data.oci_core_instance.existing[0].shape
    availability_domain = data.oci_core_instance.existing[0].availability_domain
  }
}

output "vnic_attachments" {
  value = var.instance_id == "" ? [] : [for item in data.oci_core_vnic_attachments.instance[0].vnic_attachments : {
    id      = item.id
    vnic_id = item.vnic_id
  }]
}
