provider "aws" {
  profile = "personal"
  region = "${var.aws_region}"
}

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
  policy =<<POLICY
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
