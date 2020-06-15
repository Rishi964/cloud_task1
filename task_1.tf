provider "aws" {
  region  = "ap-south-1"
  profile = "Rishabh"
}

//key-pair

resource "tls_private_key" "task1_private_key" {
  algorithm   = "RSA"
  rsa_bits = 4096

}

resource "aws_key_pair" "task1_public_key" {
  key_name   = "task1_public_key"
  public_key = tls_private_key.task1_private_key.public_key_openssh
}


//security-group

resource "aws_security_group" "task1_SG" {
  name = "task1_SG"
  description = "Allow TCP inbound traffic"

  ingress {
    description = "SSH port from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP port from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  tags = {
    Name = "task1_SG"
  }
}


// ebs-instance

resource "aws_instance" "task1_os" {
  ami             = "ami-0447a12f28fddb066"
  instance_type   = "t2.micro"
  security_groups = [ "task1_SG" ]  
  key_name        = aws_key_pair.task1_public_key.key_name
  
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task1_private_key.private_key_pem
    host     = aws_instance.task1_os.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"
    ]
  }

  tags = {
    Name = "task1_os"
  }
}



//ebs-volume

resource "aws_ebs_volume" "task1_ebs" {
  availability_zone = aws_instance.task1_os.availability_zone
  size  = 1

  tags = {
    Name = "task1_ebs"
  }
}

resource "aws_volume_attachment" "task1_ebs_attach" {
  depends_on = [ aws_ebs_volume.task1_ebs, ]
 
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.task1_ebs.id
  instance_id = aws_instance.task1_os.id
  force_detach = true
}


//remote-execution

resource "null_resource" "remote-exec1" {
  
  depends_on = [
    aws_volume_attachment.task1_ebs_attach,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task1_private_key.private_key_pem
    host     = aws_instance.task1_os.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Rishi964/cloud_task1.git /var/www/html/"
    ]
  }
}


//ebs-snapshot

resource "aws_ebs_snapshot" "snapshot" {
  depends_on = [null_resource.remote-exec1] 
  volume_id  = aws_ebs_volume.task1_ebs.id

  tags = {
    Name = "ebs_snapshot"
  }
}


//s3-bucket-create

resource "aws_s3_bucket" "task1-cloud-bucket" {  
  bucket = "task1-cloud-bucket"
  acl    = "public-read"
  region = "ap-south-1"

  tags = {
    Name  = "task1-cloud-bucket"
  }
}


resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.task1-cloud-bucket.id
  key    = "image.jpg"
  source = "C:/Users/Risha/Downloads/image.jpg"
  content_type = "image/jpg"
  acl = "public-read"
}




//cloudfront create

locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "this is the origin access identity"
}


resource "aws_cloudfront_distribution" "s3_distribution" {
  
  origin {
    domain_name = aws_s3_bucket.task1-cloud-bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.task1_private_key.private_key_pem
    host     = aws_instance.task1_os.public_ip
  }
  
  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/CF_domain/${aws_cloudfront_distribution.s3_distribution.domain_name}/' /var/www/html/index.html",
      "sudo systemctl restart httpd"
    ]
  }

  depends_on = [ aws_s3_bucket.task1-cloud-bucket, ]
}



data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.task1-cloud-bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.task1-cloud-bucket.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket-policy" {
  bucket = aws_s3_bucket.task1-cloud-bucket.id
  policy = data.aws_iam_policy_document.s3_policy.json
}




//execute chrome

resource "null_resource" "local-exec1"  {
  depends_on = [
    aws_cloudfront_distribution.s3_distribution,
  ]

  provisioner "local-exec" {
    command = "chrome ${aws_instance.task1_os.public_ip}"
  }
}



output "domain" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}