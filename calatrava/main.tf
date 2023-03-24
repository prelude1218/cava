variable "user" {
  
}

variable "nsname" {

}

variable "cspToken"{

}

variable "description"{

}

terraform {
  required_providers {
    pacific = {
      # The legacy locally installed pacific provider
      # source = "eng.vmware.com/calatrava/pacific"

      source = "cdickmann-terraform-registry.object1-wdc.calatrava.vmware.com/terraform-registry/pacific"
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

  # To deploy to on-prem use calatrava-sc/calatrava-wdc
  region  = "calatrava-wdc"
  class   = "calatrava-default"
  description = var.description
}

# save kubeconfig to "supervisor namespace", i.e. our "cloud API"
resource "local_file" "sv_kubeconfig" {
  sensitive_content = pacific_ccs_namespace.ns.kubeconfig
  filename          = "${path.module}/sv.kubeconfig"
  file_permission   = "0644"
}

resource "pacific_guestcluster" "tkc" {
  cluster_name     = "tkc"
  namespace        = pacific_ccs_namespace.ns.namespace
  input_kubeconfig = pacific_ccs_namespace.ns.kubeconfig
  # versions older than v1.20 are deprecated
  version                            = "v1.23" #Latest v1.23 in region calatrava-wdc/calatrava-sc
  network_servicedomain              = "cluster.local"
  # vault = true  #uncomment to enable vault operator
  # cert_manager = true #uncomment to enable cert manager operator
  # external_dns = true #uncomment to enable external-dns operator
  topology_controlplane_class        = "best-effort-small"
  topology_controlplane_count        = 1      #3 nodes are recommended for prod and stage work load for high availability and 1 for test workload
  topology_controlplane_storageclass = pacific_ccs_namespace.ns.storageclasses[0]
  storage_defaultclass               = pacific_ccs_namespace.ns.storageclasses[0]
  topology_nodepool {
        name = "workers"
        node_drain_timeout = "10m"  #change this value to 0m if you want to stop supervisor controller from performing a forced node drain in 10m during tkc updates.
        class = "best-effort-small"
        count = 3
        storageclass = pacific_ccs_namespace.ns.storageclasses[0]
  }
  tags = {
    foo = "foo-1"
    bar = "bar-1"
  }
}

// save kubeconfig
resource "local_file" "tkc_kubeconfig" {
  #sensitive_content = pacific_guestcluster.tkc.kubeconfig
  filename          = "${path.module}/tkc.kubeconfig"
  file_permission   = "0644"
}
