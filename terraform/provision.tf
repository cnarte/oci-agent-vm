# Optional full provisioning example. It is disabled by default so the first plan is read-only.

locals {
  provision_compartment = var.compartment_ocid != "" ? var.compartment_ocid : var.tenancy_ocid
}

data "oci_core_images" "ubuntu_arm64" {
  count                    = var.enable_provisioning ? 1 : 0
  compartment_id           = local.provision_compartment
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_vcn" "agent" {
  count          = var.enable_provisioning ? 1 : 0
  compartment_id = local.provision_compartment
  display_name   = "${var.instance_name}-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
}

resource "oci_core_internet_gateway" "agent" {
  count          = var.enable_provisioning ? 1 : 0
  compartment_id = local.provision_compartment
  vcn_id         = oci_core_vcn.agent[0].id
  display_name   = "${var.instance_name}-igw"
  enabled        = true
}

resource "oci_core_route_table" "agent" {
  count          = var.enable_provisioning ? 1 : 0
  compartment_id = local.provision_compartment
  vcn_id         = oci_core_vcn.agent[0].id
  display_name   = "${var.instance_name}-routes"
  route_rules {
    network_entity_id = oci_core_internet_gateway.agent[0].id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_security_list" "agent" {
  count          = var.enable_provisioning ? 1 : 0
  compartment_id = local.provision_compartment
  vcn_id         = oci_core_vcn.agent[0].id
  display_name   = "${var.instance_name}-security"

  ingress_security_rules {
    protocol    = "6"
    source      = var.ssh_ingress_cidr
    source_type = "CIDR_BLOCK"
    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "agent" {
  count                      = var.enable_provisioning ? 1 : 0
  compartment_id             = local.provision_compartment
  vcn_id                     = oci_core_vcn.agent[0].id
  display_name               = "${var.instance_name}-subnet"
  cidr_block                 = "10.0.1.0/24"
  route_table_id             = oci_core_route_table.agent[0].id
  security_list_ids          = [oci_core_security_list.agent[0].id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_instance" "agent" {
  count               = var.enable_provisioning ? 1 : 0
  compartment_id      = local.provision_compartment
  availability_domain = var.availability_domain
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }
  create_vnic_details {
    subnet_id        = oci_core_subnet.agent[0].id
    assign_public_ip = true
    display_name     = "${var.instance_name}-vnic"
  }
  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }
  is_pv_encryption_in_transit_enabled = true
  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_arm64[0].images[0].id
  }
  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("${path.module}/../bootstrap/cloud-init.yaml"))
  }
}
