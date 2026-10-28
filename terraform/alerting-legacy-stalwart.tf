# Legacy Stalwart dashboards
#
# The production dashboard uses static environment selectors in its JSON model
# while the log-derived signals are being validated before alert rules are added.

resource "grafana_dashboard" "legacy_stalwart_prod" {
  folder      = grafana_folder.legacy_services.id
  config_json = file("${path.module}/dashboards/legacy-services/stalwart-prod.json")
}
