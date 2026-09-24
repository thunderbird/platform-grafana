# Legacy Stalwart dashboards
#
# The stage and production dashboards intentionally live as separate resources
# and use static environment selectors in their JSON models. This keeps the
# dashboards safe to share independently while the log-derived signals are
# being validated before alert rules are added.

resource "grafana_dashboard" "legacy_stalwart_stage" {
  folder      = grafana_folder.legacy_services.id
  config_json = file("${path.module}/dashboards/legacy-services/stalwart-stage.json")
}

resource "grafana_dashboard" "legacy_stalwart_prod" {
  folder      = grafana_folder.legacy_services.id
  config_json = file("${path.module}/dashboards/legacy-services/stalwart-prod.json")
}
