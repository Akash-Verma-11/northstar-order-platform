output "region" {
  value = var.aws_region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "ebs_csi_role_arn" {
  value = module.ebs_csi_irsa.iam_role_arn
}

output "ecr_api" {
  value = aws_ecr_repository.api.repository_url
}

output "ecr_worker" {
  value = aws_ecr_repository.worker.repository_url
}

output "ecr_frontend" {
  value = aws_ecr_repository.frontend.repository_url
}
