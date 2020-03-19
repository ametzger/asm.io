provider "aws" {
  profile = "personal"
  region  = "${var.aws_region}"
  version = "~> 2.43.0"
}

################################################################################
# Existing Data ################################################################
################################################################################

data "aws_route53_zone" "main" {
  name         = "${var.site_url}."
  private_zone = false
}

################################################################################
# S3 ###########################################################################
################################################################################

resource "aws_s3_bucket" "logs" {
  bucket = "${var.site_url}-logs"
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket" "main" {
  bucket = "${var.site_url}"
  acl    = "public-read"

  website {
    index_document = "index.html"
    error_document = "404.html"
  }

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  logging {
    target_bucket = "${aws_s3_bucket.logs.id}"
    target_prefix = "logs/"
  }
}

resource "aws_s3_bucket_policy" "main_public" {
  bucket = "${aws_s3_bucket.main.id}"

  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[{
    "Sid":"AllowPublicAccess",
    "Effect":"Allow",
	  "Principal": "*",
    "Action":["s3:GetObject"],
    "Resource":["arn:aws:s3:::${var.site_url}/*"]
  }]
}
POLICY
}

################################################################################
# ACM ##########################################################################
################################################################################

resource "aws_acm_certificate" "main" {
  domain_name               = "${var.site_url}"
  subject_alternative_names = ["*.${var.site_url}"]
  validation_method         = "DNS"

  tags {
    Name = "${var.site_url}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "main_validation" {
  name    = "${aws_acm_certificate.main.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.main.domain_validation_options.0.resource_record_type}"
  zone_id = "${data.aws_route53_zone.main.id}"
  records = ["${aws_acm_certificate.main.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = "${aws_acm_certificate.main.arn}"
  validation_record_fqdns = ["${aws_route53_record.main_validation.fqdn}"]
}

################################################################################
# Lambda #######################################################################
################################################################################
provider "archive" {}

resource "aws_iam_role" "lambda_role" {
  name = "web-lambda-role"

  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow"
      },
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "edgelambda.amazonaws.com"
        },
        "Effect": "Allow"
      }
    ]
  }
  EOF
}

data "archive_file" "http_headers_lambda" {
  type = "zip"

  source {
    content  = "${file("${path.module}/http-headers.js")}"
    filename = "http-headers.js"
  }

  output_path = "http-headers.zip"
}

resource "aws_lambda_function" "http_headers" {
  function_name    = "web-http-headers"
  role             = "${aws_iam_role.lambda_role.arn}"
  handler          = "http-headers.handler"
  runtime          = "nodejs10.x"
  publish          = true
  filename         = "${data.archive_file.http_headers_lambda.output_path}"
  source_code_hash = "${data.archive_file.http_headers_lambda.output_base64sha256}"
}

resource "aws_cloudwatch_log_group" "http_headers" {
  name = "/aws/lambda/${aws_lambda_function.http_headers.function_name}"
}

################################################################################
# CloudFront ###################################################################
################################################################################
locals {
  s3_origin_id = "${var.site_url}-S3"
}

resource "aws_cloudfront_distribution" "main" {
  origin {
    # HACK: This doesn't appear to actually give the regional domain,
    # so manually construct it.
    # domain_name = "${aws_s3_bucket.main.bucket_regional_domain_name}"
    domain_name = "${aws_s3_bucket.main.bucket}.s3-website-${var.aws_region}.amazonaws.com"

    origin_id = "${local.s3_origin_id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  wait_for_deployment = false

  aliases = ["${var.site_url}", "www.${var.site_url}"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"
    compress         = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type   = "origin-response"
      lambda_arn   = "${aws_lambda_function.http_headers.qualified_arn}"
      include_body = false
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    acm_certificate_arn      = "${aws_acm_certificate.main.arn}"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }

  logging_config {
    include_cookies = false
    bucket          = "${aws_s3_bucket.logs.bucket_domain_name}"
    prefix          = "cdn-${var.site_url}"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }
  }

  lifecycle {
    # HACK: Terraform seems to fuck this up, not sure why.
    ignore_changes = ["origin"]
  }
}

################################################################################
# Route53 ######################################################################
################################################################################

resource "aws_route53_record" "naked" {
  zone_id = "${data.aws_route53_zone.main.zone_id}"
  name    = "${var.site_url}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.main.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.main.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "nakedv6" {
  zone_id = "${data.aws_route53_zone.main.zone_id}"
  name    = "${var.site_url}"
  type    = "AAAA"

  alias {
    name                   = "${aws_cloudfront_distribution.main.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.main.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = "${data.aws_route53_zone.main.zone_id}"
  name    = "www.${var.site_url}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.main.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.main.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wwwv6" {
  zone_id = "${data.aws_route53_zone.main.zone_id}"
  name    = "www.${var.site_url}"
  type    = "AAAA"

  alias {
    name                   = "${aws_cloudfront_distribution.main.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.main.hosted_zone_id}"
    evaluate_target_health = false
  }
}
