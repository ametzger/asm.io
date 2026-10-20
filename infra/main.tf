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

  depends_on = [aws_s3_bucket_ownership_controls.logs]

  access_control_policy {
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

data "aws_iam_policy_document" "access_log_delivery" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/logs/*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.access_log_delivery.json
}

resource "aws_s3_bucket" "main" {
  bucket = var.site_url
}

resource "aws_s3_bucket_ownership_controls" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
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
# CloudFront ###################################################################
################################################################################
locals {
  s3_origin_id = "${var.site_url}-S3"

  site_html     = join("", [for f in fileset("${path.module}/../site", "**/*.html") : file("${path.module}/../site/${f}")])
  script_hashes = [for m in regexall("(?s)<script[^>]*>(.*?)</script>", local.site_html) : "'sha256-${base64sha256(m[0])}'"]
  style_hashes  = [for m in regexall("(?s)<style[^>]*>(.*?)</style>", local.site_html) : "'sha256-${base64sha256(m[0])}'"]
}

resource "aws_cloudfront_function" "url_rewrite" {
  name    = "web-url_rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/url-rewrite.js")
}

resource "aws_cloudfront_origin_access_control" "main" {
  name                              = var.site_url
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name              = aws_s3_bucket.main.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  wait_for_deployment = false

  aliases = [var.site_url, "www.${var.site_url}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id
    compress         = true
    cache_policy_id  = data.aws_cloudfront_cache_policy.caching_optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.url_rewrite.arn
    }

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    viewer_protocol_policy = "redirect-to-https"
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
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
      range(500, 505)
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
      content_security_policy = "default-src 'self'; script-src ${join(" ", local.script_hashes)}; style-src ${join(" ", local.style_hashes)}; manifest-src 'self'; base-uri 'self'; object-src 'none';"

      override = true
    }
  }
}

data "aws_iam_policy_document" "cloudfront_access" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
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
