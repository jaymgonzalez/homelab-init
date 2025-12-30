# GitLab Configuration Module

This Terraform module manages GitLab resources using the GitLab provider.

## Purpose

- Creates and manages the `proxmox-iac` GitLab project
- Optionally creates a GitLab group to organize projects
- Provides outputs for Git URLs and Terraform state backend configuration

## Prerequisites

1. GitLab instance deployed and accessible
2. GitLab personal access token with scopes:
   - `api` - Full API access
   - `read_repository` - Read repository
   - `write_repository` - Write repository

## Usage

1. **Copy the example tfvars file:**
   ```bash
   cd terraform/gitlab-config
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values:**
   - Set `gitlab_url` to your GitLab instance URL
   - Set `gitlab_token` to your personal access token
   - Adjust project settings as needed

3. **Initialize and apply:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **View outputs:**
   ```bash
   terraform output
   ```

## Important Notes

- The `terraform.tfvars` file is gitignored to protect your token
- This module creates the project with `initialize_with_readme = false` since we're migrating existing code
- The Terraform state for this module is stored locally initially, then can be migrated to GitLab after the project is created

## Outputs

After applying, you'll get:
- `project_url` - Web URL to access the project
- `http_url` - HTTP clone URL for Git
- `ssh_url` - SSH clone URL for Git
- `terraform_state_url` - Base URL for Terraform HTTP backend state storage
