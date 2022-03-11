variable "aws_region" {
  description = "AWS region"
}

variable "site_url" {
  description = "URL of the site to provision"
}

variable "additional_urls" {
  default     = []
  description = "Alternate URLs that should point to site"
}
