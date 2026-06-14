# ECR Module

This module creates and manages Amazon Elastic Container Registry (ECR) repositories for storing Docker container images.

## Features

- Creates ECR repositories with configurable settings
- Implements lifecycle policies for image management
- Configures image scanning on push
- Supports cross-account access policies
- Encrypts images at rest using AES256
- Provides comprehensive outputs for integration

## Usage

```hcl
module "ecr" {
  source = "./modules/ecr"

  stack_name = "myapp"
  env        = "prod"
  
  repositories = [
    {
      name                 = "web-app"
      image_tag_mutability = "MUTABLE"
      scan_on_push         = true
      enable_cross_account_access = false
      lifecycle_policy = {
        keep_last_images     = 15
        untagged_expire_days = 3
      }
    },
    {
      name                 = "api-service"
      image_tag_mutability = "IMMUTABLE"
      scan_on_push         = true
      enable_cross_account_access = true
    }
  ]

  allowed_principals = [
    "arn:aws:iam::ACCOUNT-ID:root"
  ]

  additional_tags = {
    Environment = "production"
    Team        = "devops"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| stack_name | Name of the stack | string | n/a | yes |
| env | Environment name | string | n/a | yes |
| repositories | List of ECR repositories to create | list(object) | [] | no |
| allowed_principals | List of AWS principals allowed to pull from ECR | list(string) | [] | no |
| additional_tags | Additional tags to apply to ECR resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| repository_urls | Map of repository names to their URLs |
| repository_arns | Map of repository names to their ARNs |
| repository_registry_ids | Map of repository names to their registry IDs |
| repository_names | List of created repository names |
| account_id | AWS Account ID |

## Repository Configuration

Each repository in the `repositories` list supports:

- `name`: Repository name (required)
- `image_tag_mutability`: MUTABLE or IMMUTABLE (default: MUTABLE)
- `scan_on_push`: Enable vulnerability scanning (default: true)
- `enable_cross_account_access`: Allow cross-account access (default: false)
- `lifecycle_policy`: Image lifecycle management settings
  - `keep_last_images`: Number of tagged images to keep (default: 10)
  - `untagged_expire_days`: Days to keep untagged images (default: 7)