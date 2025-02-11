output "template_id" {
  value = google_compute_instance_template.instance_template.id
}

output "health_check_id" {
  value = google_compute_health_check.health_check.id
}