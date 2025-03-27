terraform {
  required_providers {
    illumio-core = {
      source  = "illumio/illumio-core"
    }
  }
}

/*
variable "pce_url" {
  default      = "https://illumio.de.mo:8443"
  description  = "URL of the Illumio Policy Compute Engine and Web Socket (i.e., https://illumio.acme.com:8443)"
}

variable "pce_org_id" {
  default      = "2"
}

variable "pce_api_key" {
  default      = "api_16b104ab1a1057363"
}

variable "pce_api_secret" {
  default      = "9bc7ddeaf198d317c1e58791e3ceb79e83dd7d82dd40a5b3ba523395f1ccb037"
}
*/

provider "illumio-core" {
  pce_host     = var.pce_url
  api_username = var.pce_api_key
  api_secret   = var.pce_api_secret
  org_id       = var.pce_org_id
}

# Configure Labels

resource "illumio-core_label" "role_loadbalancer" {
  key   = "role"
  value = "TF-Load Balancer"
}

resource "illumio-core_label" "role_app" {
  key   = "role"
  value = "TF-App"
}

resource "illumio-core_label" "role_database" {
  key   = "role"
  value = "TF-DB"
}

resource "illumio-core_label" "role_frontend" {
  key   = "role"
  value = "TF-Frontend"
}

resource "illumio-core_label" "role_redis_leader" {
  key   = "role"
  value = "TF-Redis Leader"
}

resource "illumio-core_label" "role_redis_follower" {
  key   = "role"
  value = "TF-Redis Follower"
}

resource "illumio-core_label" "role_k8s_node" {
  key   = "role"
  value = "TF-k8s Node"
}

resource "illumio-core_label" "app_k3s" {
  key   = "app"
  value = "TF-k3s"
}

resource "illumio-core_label" "app_guestbook" {
  key   = "app"
  value = "TF-Guestbook"
}

resource "illumio-core_label" "env_production" {
  key   = "env"
  value = "TF-Production"
}

resource "illumio-core_label" "loc_demo" {
  key   = "loc"
  value = "TF-Demo"
}

# Configure Firewall Coexistence Mode (For k8s environments)

/*
resource "illumio-core_firewall_settings" "tf_k8s_fwcoexist" {
  firewall_coexistence {

    illumio_primary = true
    scope {
      href = illumio-core_label.app_k3s.href
    }
    scope {
      href = illumio-core_label.env_production.href
    }
    scope {
      href = illumio-core_label.loc_demo.href
    }
  }
}
*/

# Configure Custom Services

resource "illumio-core_service" "tf_svc_redis" {
  name        = "S-TF-Redis"
  description = "TCP and UDP Redis Service - Created by Terraform"

  service_ports {
    # Illumio uses the IANA protocol numbers to identify the service proto
    proto = "6"  # TCP
    port  = "6379"
  }

  service_ports {
    proto = "17"  # UDP
    port  = "6379"
  }
}

resource "illumio-core_service" "tf_svc_http" {
  name        = "S-TF-HTTP(S)"
  description = "HTTP and HTTPS Service - Created by Terraform"

  service_ports {
    proto = "6"
    port  = "80"
  }

  service_ports {
    proto = "6"
    port  = "443"
  }
}

resource "illumio-core_service" "tf_svc_alt_http" {
  name        = "S-TF-Alt-HTTP(S)"
  description = "Alternative HTTP and HTTPS Service - Created by Terraform"

  service_ports {
    proto = "6"
    port  = "8080"
  }

  service_ports {
    proto = "6"
    port  = "8443"
  }
}

resource "illumio-core_service" "tf_svc_dns" {
  name        = "S-TF-DNS"
  description = "DNS Service - Created by Terraform"

  service_ports {
    proto = "6"
    port  = "53"
  }

  service_ports {
    proto = "17"
    port  = "53"
  }
}

resource "illumio-core_service" "tf_svc_kube_api" {
  name        = "S-TF-Kube API"
  description = "TCP 6443 - Kube API Service - Created by Terraform"

  service_ports {
    proto = "6"  
    port  = "6443"
  }
}

resource "illumio-core_service" "tf_svc_kube_etcd" {
  name        = "S-TF-Kube etcd"
  description = "DNS Service - Created by Terraform"

  service_ports {
    proto   = "6"
    port    = "2379"
    to_port = "2380"
  }

  service_ports {
    proto   = "17"
    port    = "2379"
    to_port = "2380"
  }
}

resource "illumio-core_service" "tf_svc_clas" {
  name        = "S-TF-CLAS"
  description = "CLAS Service - Created by Terraform"

  service_ports {
    proto = "6"
    port  = "9000"
  }
}

resource "illumio-core_service" "tf_svc_etcd" {
  name        = "S-TF-ETCD"
  description = "etcd Service - Created by Terraform"

  service_ports {
    proto = "6"
    port  = "2379"
  }
}

resource "illumio-core_service" "tf_svc_cven" {
  name        = "S-TF-CVEN"
  description = "CVEN Service - Created by Terraform"

  service_ports {
    proto = "6"
    port  = "8080"
  }

  service_ports {
    proto = "6"
    port  = "8081"
  }
  
  service_ports {
    proto = "6"
    port = "9000"
  }
}

data "illumio-core_services" "all_services" {
  name = "All Services"
  max_results = 1
}

# Configure IP Lists

data "illumio-core_ip_lists" "default" {
  # all PCE instances define a special default IP list covering all addresses
  name = "Any (0.0.0.0/0 and ::/0)"
  max_results = 1
}

resource "illumio-core_ip_list" "tf_ipl_users" {
  name          = "TF-IPL-VPN Users"
  description   = "VPN Users IP List - Created by Terraform"

  ip_ranges {
    from_ip     = "10.211.0.0/24"
    description = "VPN User network CIDR"
  }

  fqdns {
    fqdn        = "*.zt-demo.com"
    description = "Zero Trust Demo Domain"
  }

  fqdns {
    fqdn        = "*.de.mo"
    description = "Demo Domain"
  }
}

resource "illumio-core_ip_list" "tf_ipl_illumio" {
  name          = "TF-IPL-Illumio"
  description   = "Illumio PCE Cluster IP List - Created by Terraform"

  ip_ranges {
    from_ip     = "10.30.1.1"
    to_ip       = "10.30.1.2"
    description = "Illumio PCE Core Node(s) network range"
  }
  
  ip_ranges {
    from_ip     = "172.16.11.60"
    description = "Illumio PCE VIP"
  }

  fqdns {
    fqdn        = "core*.de.mo"
    description = "Illumio PCE Core Nodes FQDN"
  }

  fqdns {
    fqdn        = "illumio.de.mo"
    description = "Illumio PCE VIP FQDN"
  }
}

resource "illumio-core_ip_list" "tf_ipl_k8s_registry" {
  name          = "TF-IPL-K8s Registry"
  description   = "K8s Registry IP List - Created by Terraform"

  fqdns {
    fqdn        = "*.docker.io"
  }

  fqdns {
    fqdn        = "privateregistry.example.com"
  }
}

resource "illumio-core_ip_list" "tf_ipl_k8s_kubelink" {
  name          = "TF-IPL-illumio-kubelink"
  description   = "Illumio Kubelink IP List - Created by Terraform"

  fqdns {
    fqdn        = "illumio-kubelink-*"
    description = "All Illumio Kubelink Pods"
  }
}

resource "illumio-core_ip_list" "tf_ipl_k8s_storage" {
  name          = "TF-IPL-illumio-storage"
  description   = "Illumio Storage IP List - Created by Terraform"
  
  fqdns {       
    fqdn        = "illumio-storage-*"
    description = "All Illumio Storage Pods"
  }
}

resource "illumio-core_ip_list" "tf_ipl_k8s_pod_nets" {
  name          = "TF-IPL-K8s Pod Networks"
  description   = "K8s Pod Network IP List - Created by Terraform"

  ip_ranges {
    from_ip     = "10.42.0.0/16"
    description = "K8s Pod Network"
  }

  ip_ranges {
    from_ip     = "10.100.0.0/16"
    description = "Alternate K8s Pod Network"
  }
}

resource "illumio-core_ip_list" "tf_ipl_k8s_svc_nets" {
  name          = "TF-IPL-K8s Services Networks"
  description   = "K8s Services Network IP List - Created by Terraform"

  ip_ranges {
    from_ip     = "10.43.0.0/16"
    description = "K8s Pod Network"
  }

  ip_ranges {
    from_ip     = "10.200.0.0/16"
    description = "Alternate K8s Pod Network"
  }
}

# Configure Illumio Security Ruleset

resource "illumio-core_rule_set" "tf_k8s_ruleset" {
  name = "TF-RS | K8s - Guestbook"

  scopes {
    label {
      href = illumio-core_label.loc_demo.href
    }

    label {
      href = illumio-core_label.env_production.href
    }

    label {
      href = illumio-core_label.app_guestbook.href
    }
  }
}

resource "illumio-core_rule_set" "tf_k8s_core_ruleset" {
  name = "TF-RS | K8s - Essential Services"

  scopes {
    label {
      href = illumio-core_label.loc_demo.href
    }

    label {
      href = illumio-core_label.env_production.href
    }

    label {
      href = illumio-core_label.app_k3s.href
    }
  }
}

# Configure Illumio Security Rules

resource "illumio-core_security_rule" "tf_k8s_rule0" {
  rule_set_href = illumio-core_rule_set.tf_k8s_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["virtual_services"]
  }

  consumers {
    #actors = "ams"  # special notation meaning "all managed systems" - affects all workloads
    label {
      href = illumio-core_label.role_redis_follower.href
    }
  }

  providers {
    #actors = "ams"
    label {
      href = illumio-core_label.role_redis_leader.href
    }
  }
/*
  ingress_services {

    # Uncomment if using 'All Services'    
    #href = one(data.illumio-core_services.all_services.items[*].href)
    href = illumio-core_service.tf_svc_redis.href
  }
*/
}

resource "illumio-core_security_rule" "tf_k8s_rule_1" {
  rule_set_href = illumio-core_rule_set.tf_k8s_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_users.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_frontend.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_http.href
  }
}

resource "illumio-core_security_rule" "tf_k8s_rule2" {
  rule_set_href = illumio-core_rule_set.tf_k8s_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    label {
      href = illumio-core_label.role_redis_follower.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_redis_leader.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_redis.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_rule3" {
  rule_set_href = illumio-core_rule_set.tf_k8s_ruleset.href

  enabled = true

  # Extra-Ruleset
  unscoped_consumers = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }
  
  consumers {
    label {
      href = illumio-core_label.role_k8s_node.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_frontend.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_http.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_rule4" {
  rule_set_href = illumio-core_rule_set.tf_k8s_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["virtual_services"]
  }

  consumers {
    label {
      href = illumio-core_label.role_frontend.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_redis_leader.href
    }
  }

}

resource "illumio-core_security_rule" "tf_k8s_rule5" {
  rule_set_href = illumio-core_rule_set.tf_k8s_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["virtual_services"]
  }

  consumers {
    label {
      href = illumio-core_label.role_frontend.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_redis_follower.href
    }
  }

}

resource "illumio-core_security_rule" "tf_k8s_rule6" {
  rule_set_href = illumio-core_rule_set.tf_k8s_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    label {
      href = illumio-core_label.role_frontend.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_redis_leader.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_redis.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_rule7" {
  rule_set_href = illumio-core_rule_set.tf_k8s_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    label {
      href = illumio-core_label.role_frontend.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_redis_follower.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_redis.href
  }

}

## K8s Core Services Rulesets

resource "illumio-core_security_rule" "tf_k8s_req_rule0" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    actors = "ams"  # special notation meaning "all managed systems" - affects all workloads
  }

  providers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_registry.href
    }
  }

  ingress_services {
    href = one(data.illumio-core_services.all_services.items[*].href)
  }
}

resource "illumio-core_security_rule" "tf_k8s_req_rule1" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    label {
      href = illumio-core_label.role_k8s_node.href
    }
  }

  providers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_illumio.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_alt_http.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule2" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["virtual_services"]
    providers = ["workloads"]
  }

  consumers {
    actors = "ams"
  }

  providers {
    actors = "ams"
  }

  ingress_services {
    href = one(data.illumio-core_services.all_services.items[*].href)
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule3" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_pod_nets.href
    }
  }

  providers {
    actors = "ams"
  }

  ingress_services {
    href = illumio-core_service.tf_svc_dns.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule4" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    actors = "ams"
  }

  providers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_pod_nets.href
    }
  }

  ingress_services {
    href = one(data.illumio-core_services.all_services.items[*].href)
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule5" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    label {
      href = illumio-core_label.role_k8s_node.href
    }
  }

  providers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_svc_nets.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_clas.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule6" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    ip_list {
      href = one(data.illumio-core_ip_lists.default.items[*].href)
    }
  }

  providers {
    label {
      href = illumio-core_label.role_k8s_node.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_kube_etcd.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule7" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_kubelink.href
    }
  }

  providers {
    actors = "ams"
  }

  ingress_services {
    href = illumio-core_service.tf_svc_etcd.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule8" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    actors = "ams"
  }

  providers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_storage.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_etcd.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule9" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    label {
      href = illumio-core_label.role_k8s_node.href
    }
  }

  providers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_kubelink.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_cven.href
  }

}

/*
resource "illumio-core_security_rule" "tf_k8s_req_rule10" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_kubelink.href
    }
  }

  providers {
    labels {
    # Insert Illumio Labels      
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_alt_http.href
  }

}
*/

resource "illumio-core_security_rule" "tf_k8s_req_rule11" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_kubelink.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_k8s_node.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_http.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule12" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_k8s_pod_nets.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_k8s_node.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_kube_api.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_req_rule13" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }

  consumers {
    ip_list {
      href = illumio-core_ip_list.tf_ipl_users.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_k8s_node.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_http.href
  }

}

resource "illumio-core_security_rule" "tf_k8s_rule14" {
  rule_set_href = illumio-core_rule_set.tf_k8s_core_ruleset.href

  enabled = true

  unscoped_consumers = true

  resolve_labels_as {
    consumers = ["workloads"]
    providers = ["workloads"]
  }
  
  consumers {
    label {
      href = illumio-core_label.role_redis_follower.href
    }
  }

  providers {
    label {
      href = illumio-core_label.role_k8s_node.href
    }
  }

  ingress_services {
    href = illumio-core_service.tf_svc_redis.href
  }

}

# Configure K8s Pairing Profile

resource "illumio-core_pairing_profile" "tf_k8s_pp" {
  name                  = "TF-K8s Pairing Profile"
  enabled               = true
  
  enforcement_mode      = "visibility_only" # idle, visibility_only, full, selective
  enforcement_mode_lock = true
 
  allowed_uses_per_key  = "unlimited" # unlimited, or value (1-2147483647)
  key_lifespan          = "unlimited" # unlimited, or value (in seconds)
  
  role_label_lock       = true
  app_label_lock        = true
  env_label_lock        = true
  loc_label_lock        = true

  log_traffic           = false
  log_traffic_lock      = true

  visibility_level      = "flow_summary" # flow_summary, flow_drops, flow_off, enhanced_data_collection
  visibility_level_lock = false

  labels {
    href = illumio-core_label.loc_demo.href
  }
 
  labels {
    href = illumio-core_label.env_production.href
  }

  labels {
    href = illumio-core_label.app_k3s.href
  }

  labels {
    href = illumio-core_label.role_k8s_node.href
  }
}

# Generate Pairing Key

/*
resource "illumio-core_pairing_keys" "tf_k8s_pp_key" {
  pairing_profile_href = illumio-core_pairing_profile.tf_k8s_pp.href
  token_count = 1
}
*/

# Configure Container Cluster

resource "illumio-core_container_cluster" "tf_k3s_cc" {
  name        = "TF-K3s Container Cluster"
  description = "Kubernetes Container Cluster created through Terraform"
}

# Configure Container Cluster Workload Profile

/*
resource "illumio-core_container_cluster_workload_profile" "tf_k3s_ccwp" {
  container_cluster_href = illumio-core_container_cluster.tf_k3s_cc.href
  name                   = "Container Cluster Workload Profile"
  description            = "Container Cluster Workload Profile created by Terraform"
  managed                = true
  enforcement_mode       = "visibility_only" # Options are: idle, visibility_only, selective, full

  labels {
    key  = "loc"
    assignment {
      href = illumio-core_label.loc_demo.href
    }
  }

  labels {
    key  = "env"
    assignment {
      href = illumio-core_label.env_production.href
    }
  }
  
  labels {
    key  = "app"
    assignment { 
      href = illumio-core_label.app_guestbook.href
    }
  }
}
*/

output "tf_pce_url" {
  value = var.pce_url
}

output "tf_pce_org_id" {
  value = var.pce_org_id
}

output "tf_pce_api_key" {
  value = var.pce_api_key
}

output "tf_pce_api_secret" {
  value = var.pce_api_secret
  sensitive = true
}

output "tf_k8s_pp" {
  value = illumio-core_pairing_profile.tf_k8s_pp.href
}

/*
output "tf_k8s_pp_key" {
  value = illumio-core_pairing_keys.tf_k8s_pp_key.activation_tokens
}
*/

output "tf_k3s_cc_id" {
  value = illumio-core_container_cluster.tf_k3s_cc.container_cluster_id
}

output "tf_k3s_cc_token" {
  value = illumio-core_container_cluster.tf_k3s_cc.container_cluster_token
  sensitive = true
}

output "tf_label_loc" {
  value = illumio-core_label.loc_demo.href
}

output "tf_label_env" {
  value = illumio-core_label.env_production.href
}

output "tf_label_app" {
  value = illumio-core_label.app_k3s.href
}

output "tf_label_k8s_app" {
  value = illumio-core_label.app_guestbook.href
}
