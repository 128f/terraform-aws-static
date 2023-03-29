terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# the bucket where our static files will be hosted
resource "aws_s3_bucket" "static" {
  bucket = var.site-name
}

# the bucket will host a website
resource "aws_s3_bucket_website_configuration" "static_site" {
  bucket = aws_s3_bucket.static.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# bucket is public readable
resource "aws_s3_bucket_acl" "public_read" {
  bucket = aws_s3_bucket.static.id
  acl    = "public-read"
}

# website policy
resource "aws_s3_bucket_policy" "static_policy" {
  bucket = aws_s3_bucket.static.id
  policy = format(file("policy.json"), var.site-name)
}

# a cloudfront distribution in front of the bucket
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = var.site-name
  }

  default_root_object            = "index.html"
  enabled             = true
  is_ipv6_enabled     = true

  aliases = [
    var.site-name,
  ]

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.site-name

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method = "sni-only"
  }
}

# register a cert
resource "aws_acm_certificate" "cert" {
  domain_name       = var.site-name
  validation_method = "DNS"

  validation_option {
    domain_name       = var.site-name
    validation_domain = var.site-name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# expect we already have a zone for this domain
data "aws_route53_zone" "primary" {
  name = var.site-name
  private_zone = false
}

# validate the cert with dns records
resource "aws_route53_record" "dns_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.primary.zone_id
}

# for use in other items
resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.dns_validation : record.fqdn]
}

# the main domain record
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.site-name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
