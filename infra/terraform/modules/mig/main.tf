resource "google_compute_instance_group_manager" "mig" {
  name = var.mig_name
  zone = "${var.location}-c"
  named_port {
    name = var.named_port_name
    port = var.named_port_port
  }
  version {
    instance_template = var.instance_template
    name              = var.instance_template_name
  }
  base_instance_name = var.base_instance_name
  target_size        = var.target_size
}