module "sipap_infra_backend" {
  source          = "../modules/tf_backend"
  stack_name      = var.stack_name
  env             = var.env
  additional_tags = var.additional_tags
}