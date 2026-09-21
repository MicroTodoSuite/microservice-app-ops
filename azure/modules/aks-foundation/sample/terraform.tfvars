# Example configuration. Identifiers the operator looks up stay empty.
client              = "lex"
project             = "mts"
environment         = "fprd"
subscription_id     = ""
location            = "eastus2"
regional_vcpu_quota = 6

network = {
  vnet_cidr        = "10.70.0.0/16"
  node_subnet_cidr = "10.70.0.0/22"
  pod_cidr         = "192.168.0.0/16"
  service_cidr     = "172.16.0.0/16"
  dns_service_ip   = "172.16.0.10"
  reserved_cidrs   = ["10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16", "10.40.0.0/16", "10.50.0.0/16"]
}

operator_cidrs = []

system_node_pool = {
  vm_size   = "Standard_D2s_v5"
  vcpus     = 2
  min_count = 1
  max_count = 3
}

cluster_admin_principal_ids = []
github_seed_subjects        = []
