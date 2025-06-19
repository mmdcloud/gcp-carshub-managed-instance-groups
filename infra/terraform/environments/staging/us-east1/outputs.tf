output "frontend_url" {
  value = module.frontend_lb.address
}

output "backend_url" {
  value = module.backend_lb.address
}