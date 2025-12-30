# =============================================================================
# GitLab Provider Variables
# =============================================================================

variable "gitlab_url" {
  description = "GitLab instance URL (e.g., http://192.168.1.50 or https://gitlab.example.com)"
  type        = string
}

variable "gitlab_token" {
  description = "GitLab personal access token with api, read_repository, and write_repository scopes"
  type        = string
  sensitive   = true
}

variable "gitlab_insecure" {
  description = "Allow insecure SSL connections (for self-signed certs)"
  type        = bool
  default     = true
}

# =============================================================================
# Project Configuration
# =============================================================================

variable "project_name" {
  description = "Name of the GitLab project"
  type        = string
  default     = "proxmox-iac"
}

variable "project_description" {
  description = "Description of the GitLab project"
  type        = string
  default     = "Proxmox Infrastructure as Code - Homelab bootstrap project"
}

variable "project_visibility" {
  description = "Project visibility level (private, internal, or public)"
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "internal", "public"], var.project_visibility)
    error_message = "Visibility must be one of: private, internal, public"
  }
}

variable "project_default_branch" {
  description = "Default branch name"
  type        = string
  default     = "main"
}

variable "enable_issues" {
  description = "Enable GitLab issues"
  type        = bool
  default     = true
}

variable "enable_wiki" {
  description = "Enable GitLab wiki"
  type        = bool
  default     = true
}

variable "enable_snippets" {
  description = "Enable GitLab snippets"
  type        = bool
  default     = true
}

variable "enable_container_registry" {
  description = "Enable container registry for this project"
  type        = bool
  default     = false
}

variable "enable_lfs" {
  description = "Enable Git LFS for this project"
  type        = bool
  default     = true
}

# =============================================================================
# Optional: Group Configuration
# =============================================================================

variable "group_name" {
  description = "Optional: GitLab group name to create project under (leave empty for personal namespace)"
  type        = string
  default     = ""
}

variable "group_path" {
  description = "Optional: GitLab group path (URL slug)"
  type        = string
  default     = ""
}
