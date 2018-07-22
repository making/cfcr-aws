resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  tags {
    Name = "${var.prefix}-cfcr-vpc"
  }
}