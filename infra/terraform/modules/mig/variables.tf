############################################
# Core / naming
############################################

variable "project_id" {
  description = "GCP project ID to deploy resources into."
  type        = string
}

variable "name" {
  description = "Base name used for the instance template, MIG, health check, and autoscaler. Must be lowercase RFC1035 compliant."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid RFC1035 label: lowercase letters, numbers, hyphens; must start with a letter."
  }
}

variable "region" {
  description = "Region for the regional Managed Instance Group, autoscaler, and health check."
  type        = string
}

variable "distribution_zones" {
  description = "Optional list of zones (within var.region) to explicitly constrain the MIG's zonal distribution policy. Leave empty to let GCP distribute across all zones in the region."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels applied to the instance template and, where supported, the MIG."
  type        = map(string)
  default     = {}
}

############################################
# Managed Instance Group configuration
############################################

variable "target_size" {
  description = "Initial number of instances. Ignored (managed by autoscaler) once autoscaling is enabled and has run once, but still required at creation."
  type        = number
  default     = 2
}

variable "description" {
  description = "Description of instance template"
  type        = string
  default     = null
}

variable "instance_template" {
  type = string
}

variable "named_ports" {
  description = "Named ports exposed by the MIG, consumed by load balancer backend services."
  type = list(object({
    name = string
    port = number
  }))
  default = []
}

variable "update_policy" {
  description = "Rolling update policy for the MIG."
  type = object({
    type                     = optional(string, "PROACTIVE") # PROACTIVE or OPPORTUNISTIC
    minimal_action           = optional(string, "REPLACE")   # REPLACE or RESTART
    max_surge_fixed          = optional(number, 3)
    max_surge_percent        = optional(number, null)
    max_unavailable_fixed    = optional(number, 0)
    max_unavailable_percent  = optional(number, null)
    replacement_method       = optional(string, "SUBSTITUTE") # SUBSTITUTE or RECREATE
  })
  default = {}
}

variable "health_check_initial_delay_sec" {
  description = "Grace period before the MIG's auto-healing policy considers a failed health check (avoids flapping during boot)."
  type        = number
  default     = 300
}

############################################
# Health check
############################################

variable "health_check" {
  description = "Health check configuration used both for auto-healing and (optionally) load balancer backends."
  type = object({
    type                = optional(string, "HTTP") # HTTP, HTTPS, TCP, SSL, HTTP2, GRPC
    port                = optional(number, 80)
    request_path        = optional(string, "/")
    check_interval_sec  = optional(number, 10)
    timeout_sec         = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 3)
  })
  default = {}
}

############################################
# Autoscaling
############################################

variable "enable_autoscaling" {
  description = "Whether to attach an autoscaler to the MIG."
  type        = bool
  default     = true
}

variable "autoscaling" {
  description = "Autoscaler configuration."
  type = object({
    min_replicas                      = optional(number, 2)
    max_replicas                      = optional(number, 10)
    cooldown_period_sec               = optional(number, 60)
    cpu_utilization_target            = optional(number, 0.6)
    cpu_predictive_method             = optional(string, "NONE") # NONE or OPTIMIZE_AVAILABILITY
    load_balancing_utilization_target = optional(number, null)   # e.g. 0.8, requires the MIG to be an LB backend
    scale_in_control = optional(object({
      max_scaled_in_replicas_fixed   = optional(number, null)
      max_scaled_in_replicas_percent = optional(number, 10)
      time_window_sec                = optional(number, 300)
    }), {})
  })
  default = {}
}
