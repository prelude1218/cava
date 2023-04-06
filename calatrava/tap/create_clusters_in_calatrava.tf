variable "user" {

}

variable "nsname" {

}

variable "cspToken"{

}

variable "description"{

}

variable "calatravaRegion"{

}

variable "kubeconfigHost"{

}

variable "kubeconfigUser"{

}

variable "kubeconfigPass"{

}

terraform {
  required_providers {
    pacific = {
      source = "cdickmann-terraform-registry.object1-wdc.calatrava.vmware.com/terraform-registry/pacific"
    }
    remote = {
      source  = "tenstad/remote"
      version = "0.1.1"
    }
  }
}

# To get your API token:
# Go to the Cloud Consumption Service in VMware Internal Org (production)
# at https://console.cloud.vmware.com/csp/gateway/portal/#/user/tokens?orgLink=%2Fcsp%2Fgateway%2Fam%2Fapi%2Forgs%2F3f4b6039-0008-433c-844c-ee9b64e3522d
# Then under **My Account**, in the **API Tokens tab**, click on `GENERATE TOKEN`
#   - Select the **Cloud Consumption Service User** role, by searching **Cascade** in the Service Roles
#   - Also check the **OpenID** scope checkbox. And click `GENERATE`
provider "pacific" {
  ccs_api_token = var.cspToken
}

# Keep the nimbus server/config/ip values, they are fine for you to use
resource "pacific_ccs_namespace" "ns" {
  project = "calatrava-project"
  user    = var.user
  name    = var.nsname

  # Right now only WDC and VMC regions are available in CCS (calatrava-vmc, calatrava-wdc)
  region  = var.calatravaRegion
  class   = "calatrava-default"
  description = var.description
}

# # save remote kubeconfig to "supervisor namespace", i.e. our "cloud API"
# resource "remote_file" "sv_kubeconfig" {
#   conn {
#     host             = var.kubeconfigHost
#     port             = 22
#     user             = var.kubeconfigUser
#     password         = var.kubeconfigPass
#   }
#   content     = pacific_ccs_namespace.ns.kubeconfig
#   path        = "${path.module}/${var.user}-${var.nsname}-sv.kubeconfig"
#   permissions = "0644"
# }

# save kubeconfig to "supervisor namespace", i.e. our "cloud API"
resource "local_file" "sv_kubeconfig" {
  sensitive_content = pacific_ccs_namespace.ns.kubeconfig
  filename          = "${path.module}/sv.kubeconfig"
  file_permission   = "0644"
}

resource "pacific_guestcluster" "tkc" {
  cluster_name     = var.nsname
  namespace        = pacific_ccs_namespace.ns.namespace
  input_kubeconfig = pacific_ccs_namespace.ns.kubeconfig
  external_dns     = true
  # versions older than v1.19 are deprecated
  version                            = "v1.23"
  network_servicedomain              = "cluster.local"
  topology_controlplane_class        = "best-effort-large"
  topology_controlplane_count        = 1      #3 nodes are recommended for prod and stage work load for high availability and 1 for test workload
  topology_controlplane_storageclass = pacific_ccs_namespace.ns.storageclasses[0]
  storage_defaultclass               = pacific_ccs_namespace.ns.storageclasses[0]
  topology_controlplane_volumes {
    name             = "containerd"
    mountpath         = "/var/lib/containerd"
    capacity_storage = "120Gi"
  }
  topology_nodepool {
        name = "workers"
        node_drain_timeout = "10m"  #change this value to 0m if you want to stop supervisor controller from performing a forced node drain in 10m during tkc updates.
        class = "best-effort-large"
        count = 3
        storageclass = pacific_ccs_namespace.ns.storageclasses[0]
        volume {
          name             = "containerd"
          mountpath         = "/var/lib/containerd"
          capacity_storage = "120Gi"
        }
  }
  tags = {
    tap_version = "TAP-1_4_1"
  }
}

# save remote kubeconfig
resource "remote_file" "tkc_kubeconfig" {
  conn {
    host             = sensitive(var.kubeconfigHost)
    port             = sensitive(22)
    user             = sensitive(var.kubeconfigUser)
    password         = sensitive(var.kubeconfigPass)
  }
  content     = pacific_guestcluster.tkc.kubeconfig
  path        = "${path.module}/${var.user}-${var.nsname}-tkc.kubeconfig"
  permissions = "0644"
}

# save kubeconfig
resource "local_file" "tkc_kubeconfig" {
  sensitive_content = pacific_guestcluster.tkc.kubeconfig
  filename          = "${path.module}/tkc.kubeconfig"
  file_permission   = "0644"
}
