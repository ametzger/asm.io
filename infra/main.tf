provider "aws" {
  region = var.aws_region
}

################################################################################
# Existing Data ################################################################
################################################################################

data "aws_canonical_user_id" "current" {}

data "aws_route53_zone" "main" {
  name         = "${var.site_url}."
  private_zone = false
}

################################################################################
# S3 ###########################################################################
################################################################################

resource "aws_s3_bucket" "logs" {
  bucket = "${var.site_url}-logs"
}

resource "aws_s3_bucket_acl" "logs" {
  bucket = aws_s3_bucket.logs.id

  access_control_policy {
    grant {
      grantee {
        type = "Group"
        uri  = "http://acs.amazonaws.com/groups/s3/LogDelivery"
      }

      permission = "READ_ACP"
    }

    grant {
      grantee {
        type = "Group"
        uri  = "http://acs.amazonaws.com/groups/s3/LogDelivery"
      }

      permission = "WRITE"
    }

    # cloudfront log delivery
    grant {
      grantee {
        id   = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
        type = "CanonicalUser"
      }

      permission = "FULL_CONTROL"
    }

    grant {
      grantee {
        id   = data.aws_canonical_user_id.current.id
        type = "CanonicalUser"
      }

      permission = "FULL_CONTROL"
    }

    owner {
      id = data.aws_canonical_user_id.current.id
    }
  }

  lifecycle {
    # NOTE(asm,2022-09-27): This conflicts with the access_control_policy element, but terraform
    # still wants to change it. I don't _think_ it matters, it's currently set to
    # `log-delivery-write` on the bucket.
    ignore_changes = [acl]
  }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket" "main" {
  bucket = var.site_url
}

resource "aws_s3_bucket_acl" "main" {
  bucket = aws_s3_bucket.main.id
  acl    = "private"
}

resource "aws_s3_bucket_logging" "main" {
  bucket = aws_s3_bucket.main.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "logs/"
}

################################################################################
# ACM ##########################################################################
################################################################################

resource "aws_acm_certificate" "main" {
  domain_name               = var.site_url
  subject_alternative_names = ["*.${var.site_url}"]
  validation_method         = "DNS"

  tags = {
    Name = var.site_url
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "main" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
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
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.main : record.fqdn]
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

data "archive_file" "url_rewrite_lambda" {
  type = "zip"

  source {
    content  = file("${path.module}/url-rewrite.js")
    filename = "url-rewrite.js"
  }

  output_path = "url-rewrite.zip"
}

resource "aws_lambda_function" "url_rewrite" {
  function_name    = "web-url_rewrite"
  role             = aws_iam_role.lambda_role.arn
  handler          = "url-rewrite.handler"
  runtime          = "nodejs20.x"
  publish          = true
  filename         = data.archive_file.url_rewrite_lambda.output_path
  source_code_hash = data.archive_file.url_rewrite_lambda.output_base64sha256
}

resource "aws_cloudwatch_log_group" "url_rewrite" {
  name = "/aws/lambda/${aws_lambda_function.url_rewrite.function_name}"
}

################################################################################
# CloudFront ###################################################################
################################################################################
locals {
  s3_origin_id    = "${var.site_url}-S3"
  s3_regional_url = "${aws_s3_bucket.main.bucket}.s3.${var.aws_region}.amazonaws.com"
}

resource "aws_cloudfront_origin_access_identity" "main" {
  comment = "${var.site_url} origin access identity"

  lifecycle {
    ignore_changes = [etag]
  }
}

resource "aws_cloudfront_distribution" "main" {
  origin {
    # HACK(asm,2022-03-10): This version of the AWS provider seems to
    # give a non-regional URL for this, so hack around that.
    # domain_name = aws_s3_bucket.main.bucket_regional_domain_name
    domain_name = local.s3_regional_url
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.main.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  wait_for_deployment = false

  aliases = [var.site_url, "www.${var.site_url}"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id
    compress         = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type   = "origin-request"
      lambda_arn   = aws_lambda_function.url_rewrite.qualified_arn
      include_body = false
    }

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.main.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cdn-${var.site_url}"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }
  }

  dynamic "custom_error_response" {
    for_each = concat(
      [400, 403, 404, 405, 414, 416],
      range(500, 504)
    )
    iterator = error_code

    content {
      error_code            = error_code.value
      response_code         = error_code.value
      response_page_path    = "/err.html"
      error_caching_min_ttl = 3600
    }
  }
}

resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "asm-security-headers"

  custom_headers_config {
    items {
      header = "Cross-Origin-Resource-Policy"
      value  = "same-origin"

      override = true
    }
  }

  remove_headers_config {
    items {
      header = "Server"
    }
  }

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    xss_protection {
      mode_block = true
      override   = true
      protection = true
    }

    content_type_options {
      override = true
    }

    referrer_policy {
      referrer_policy = "same-origin"

      override = true
    }

    frame_options {
      frame_option = "DENY"

      override = true
    }

    content_security_policy {
      content_security_policy = "default-src 'self'; script-src 'unsafe-inline' 'nonce-e4LhAepsKDMbiwG'; style-src 'nonce-MPoBxZwSEjjnUsr'; manifest-src 'self'; base-uri 'self'; object-src 'none';"

      override = true
    }
  }
}

data "aws_iam_policy_document" "cloudfront_access" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.main.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.cloudfront_access.json
}

################################################################################
# Route53 ######################################################################
################################################################################

resource "aws_route53_record" "naked" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.site_url
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "nakedv6" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.site_url
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.site_url}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wwwv6" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.site_url}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
