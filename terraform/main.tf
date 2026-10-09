data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------
# Network
# ------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.5.1"

  name = "${var.project}-${var.environment}"
  cidr = var.vpc_cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets  = ["10.40.1.0/24", "10.40.2.0/24", "10.40.3.0/24"]
  public_subnets   = ["10.40.101.0/24", "10.40.102.0/24", "10.40.103.0/24"]
  database_subnets = ["10.40.201.0/24", "10.40.202.0/24", "10.40.203.0/24"]

  enable_nat_gateway           = true
  single_nat_gateway           = true # 1 NAT gateway; false would create 3
  create_database_subnet_group = true
  enable_dns_hostnames         = true

  # Needed later by the AWS Load Balancer Controller for subnet discovery
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  tags = { Project = var.project, Environment = var.environment }
}

# ------------------------------------------------------------
# EBS CSI driver IAM role (IRSA)
# ------------------------------------------------------------
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.project}-${var.environment}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ------------------------------------------------------------
# EKS
# ------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.0.9"

  name                   = "${var.project}-${var.environment}"
  kubernetes_version     = "1.33"
  endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true # without this, nodes failed to join

  # Declaring `addons` REPLACES the module defaults, so every add-on must be
  # listed. A fresh cluster with only the EBS driver listed has no CNI and the
  # node group fails with "Unhealthy nodes".
  addons = {
    vpc-cni = {
      before_compute = true # CNI must exist before nodes try to join
    }
    kube-proxy = {}
    coredns    = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    general = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
    }
  }

  tags = { Project = var.project, Environment = var.environment }
}

# ------------------------------------------------------------
# RDS — own security group, access rule managed in code
# (previously RDS fell back to the VPC default SG, and a manual CLI rule
#  on that group blocked `terraform destroy`)
# ------------------------------------------------------------
resource "aws_security_group" "rds" {
  name_prefix = "${var.project}-${var.environment}-rds-"
  description = "Postgres access from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  tags = { Project = var.project, Environment = var.environment }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rds_from_nodes" {
  type                     = "ingress"
  description              = "Postgres from EKS node security group"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = module.eks.node_security_group_id
}

# Second source as a safety net: pod traffic may leave from the cluster
# primary SG depending on how the nodes are attached. Verify with a
# pg_isready test pod, then remove whichever rule is not needed.
resource "aws_security_group_rule" "rds_from_cluster_primary" {
  type                     = "ingress"
  description              = "Postgres from EKS cluster primary security group"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = module.eks.cluster_primary_security_group_id
}

resource "aws_db_instance" "postgres" {
  identifier            = "${var.project}-${var.environment}"
  engine                = "postgres"
  engine_version        = "17"
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "orders"
  username = "app"
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  storage_encrypted       = true
  backup_retention_period = 7
  skip_final_snapshot     = true # practice environment; set false for real data
  deletion_protection     = false

  tags = { Project = var.project, Environment = var.environment }
}

# ------------------------------------------------------------
# ECR + artifacts
# force_delete / force_destroy keep `terraform destroy` from failing
# on non-empty repos/buckets. Remove them for real production.
# ------------------------------------------------------------
resource "aws_ecr_repository" "api" {
  name         = "${var.project}/api"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = var.project, Environment = var.environment }
}

resource "aws_ecr_repository" "frontend" {
  name         = "${var.project}/frontend"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = var.project, Environment = var.environment }
}

resource "aws_ecr_repository" "worker" {
  name         = "${var.project}/worker"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = var.project, Environment = var.environment }
}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${var.project}-${var.environment}-artifacts-"
  force_destroy = true

  tags = { Project = var.project, Environment = var.environment }
}
