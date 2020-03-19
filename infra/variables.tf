variable "aws_region" {
  default     = "us-east-1"
  description = "AWS region"
}

variable "site_url" {
  default     = "asm.io"
  description = "URL of the site to provision"
}

variable "additional_urls" {
  default     = []
  description = "Alternate URLs that should point to site"
}
