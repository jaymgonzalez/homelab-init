terraform {
  required_version = ">= 1.9.5"

  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "~> 17.0"
    }
  }
}

provider "gitlab" {
  base_url = var.gitlab_url
  token    = var.gitlab_token
  insecure = var.gitlab_insecure # Set to true for self-signed certs
}
