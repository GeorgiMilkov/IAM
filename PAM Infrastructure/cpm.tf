# Once set, the module name will not be changed because if forces the VM being deleted
# and re-created.
#
# arbitrary id: mycustomvm; 01: cluster 01 ; 01: node 01 of cluster; e1: site 1 == Paris 1.
# e1 == Paris1, e2 == Paris2, e3 == Paris3 : those designations are non mandatory
# a1 == Sydney1, a2 == Sydney2, a3 == Sydney3 : those designations are non mandatory

module "cpm0101e1" {

  # This is the only possible value for this field for virtual machine
  source = "compute/vm/compute"

  # Hostname (changing this later will destroy/recreate VM)
  hostname = "cpm0101e1"

  # VM sizing
  cpus      = 8
  memory_mb = 32768

  # Tenant must know where to locate his machine.
  # EMEA: par1 | par2 | ams1
  # APAC: syd1 | syd2 | syd3
  datacenter = "par1"

  # Operating system
  os = "w2k22_gui"

  # Volumes
  volumes = [
    { size_gb = 80 }
  ]

  # Puppet tags
  tags = {
    ingenico_ecosystem = "cyberark"
    ingenico_component = "cpm"
    ingenico_instance  = "01"
    ingenico_classes   = ""
  }

  # Fixed metadata value
  metadata = var.metadata
}
