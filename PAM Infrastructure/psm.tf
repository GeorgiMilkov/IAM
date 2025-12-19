# Once set, the module name will not be changed because if forces the VM being deleted
# and re-created.
#
# arbitrary id: mycustomvm; 01: cluster 01 ; 01: node 01 of cluster; e1: site 1 == Paris 1.
# e1 == Paris1, e2 == Paris2, e3 == Paris3 : those designations are non mandatory
# a1 == Sydney1, a2 == Sydney2, a3 == Sydney3 : those designations are non mandatory


# Config for PSMP
module "psmp0101e1" {
  source     = "compute/vm/compute"
  hostname   = "psmp0101e1"
  cpus       = 8
  memory_mb  = 16384
  datacenter = "par1"
  os         = "rhel9"
  # Volumes
  volumes = [
    { size_gb = 80 }
  ]
  # Puppet tags
  tags = {
    ingenico_ecosystem = "cyberark"
    ingenico_component = "psmp"
    ingenico_instance  = "01"
    ingenico_classes   = ""
  }
  metadata = var.metadata
}
module "psm0101e1" {
  source   = "compute/vm/compute"
  hostname = "psm0101e1"
  # VM sizing
  cpus       = 8
  memory_mb  = 32768
  datacenter = "par1"
  os         = "w2k22_gui"
  # Volumes
  volumes = [
    { size_gb = 80 }
  ]
  # Puppet tags
  tags = {
    ingenico_ecosystem = "cyberark"
    ingenico_component = "psm"
    ingenico_instance  = "01"
    ingenico_classes   = "clspam_psm"
  }
  metadata = var.metadata
}
