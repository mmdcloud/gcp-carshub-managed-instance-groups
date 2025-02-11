resource "google_project_service" "project" {
  count                      = length(var.apis)
  project                    = var.project_id
  service                    = var.apis[count.index]
  disable_dependent_services = true
  disable_on_destroy         = var.disable_on_destroy
}
