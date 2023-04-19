terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

terraform {
  backend "s3" {
    bucket = "elian-terraform-state"
    key    = "HW/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "elian-terraform-state"
  }
}
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias = "europe"
  region = "eu-west-1"
}
resource "aws_s3_bucket" "elian-org-bucket" {
  bucket = "elian-org-bucket"
}
resource "aws_s3_bucket" "elian-dest-bucket" {
  bucket = "elian-dest-bucket"
  provider = aws.europe
  acl = "private"
  versioning {
    enabled = true
  }
}
resource "aws_s3_bucket_acl" "org_acl" {
  bucket = aws_s3_bucket.elian-org-bucket.id
  acl    = "private"
}
/*resource "aws_s3_bucket_acl" "dest_acl" {
  bucket = aws_s3_bucket.elian-dest-bucket.id
  acl    = "private"
}*/
data "aws_iam_policy_document" "replication_policy_data" {
    version = "2012-10-17"
    statement {
        actions   = [
            "s3:GetReplicationConfiguration",
            "s3:ListBucket"
        ]
        resources = ["arn:aws:s3:::${aws_s3_bucket.elian-org-bucket.bucket}"]
        effect    = "Allow"
    }
    statement {
        actions   = [
            "s3:GetObjectVersionForReplication",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersionTagging"
        ]
        resources = ["arn:aws:s3:::${aws_s3_bucket.elian-org-bucket.bucket}/*"]
        effect    = "Allow"
    }
    statement {
        actions   = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete",
            "s3:ReplicateTags"
        ]
        resources = ["arn:aws:s3:::${aws_s3_bucket.elian-dest-bucket.bucket}/*"]
        effect    = "Allow"
    }
}
resource "aws_iam_policy" "replication_policy" {
  name        = "replication_policy"
  description = "Replication policy for S3 bucket"
  policy      = data.aws_iam_policy_document.replication_policy_data.json
}

resource "aws_iam_role" "elian-access-role" {
  name = "elian-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Sid       = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "s3_access_policy" {
  policy_arn = aws_iam_policy.replication_policy.arn
  role       = aws_iam_role.elian-access-role.name
}
resource "aws_kms_key" "my_kms_key" {
  description = "My KMS key"
  enable_key_rotation = true
  provider = aws.europe
}
resource "aws_s3_bucket_versioning" "versioning_org" {
  bucket = aws_s3_bucket.elian-org-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
/*resource "aws_s3_bucket_versioning" "versioning_dest" {
  bucket = aws_s3_bucket.elian-dest-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}*/
resource "aws_s3_bucket_replication_configuration" "my_bucket_replication" {
  rule {
    id      = "my-replication-rule"
    status  = "Enabled"

    destination {
      bucket = "arn:aws:s3:::${aws_s3_bucket.elian-dest-bucket.bucket}"
      storage_class = "STANDARD_IA"
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.my_kms_key.arn
      }
      
    }

    source_selection_criteria {
        
        sse_kms_encrypted_objects {
            status = "Enabled"
        }
    }
    
    
  }
  

  role = aws_iam_role.elian-access-role.arn
  bucket = aws_s3_bucket.elian-org-bucket.id
}
