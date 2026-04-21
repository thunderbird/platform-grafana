module "alert_rules" {
  source = "./rules"

  prometheus_datasource_uid = var.prometheus_datasource_uid

  folder_uids = {
    thunderbird_platform = grafana_folder.thunderbird_platform.uid
    argocd          = grafana_folder.argocd.uid
    customer_health = grafana_folder.customer_health.uid
    database        = grafana_folder.database.uid
    infrastructure  = grafana_folder.infrastructure.uid
    linkerd         = grafana_folder.linkerd.uid
  }
}
