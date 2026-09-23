output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "vpc_id" { value = module.vpc.vpc_id }
output "rds_endpoint" { value = aws_db_instance.postgres.address }
output "ecr_api" { value = aws_ecr_repository.api.repository_url }
