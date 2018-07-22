locals {
    public_cidr  = "${cidrsubnet(var.vpc_cidr, 6, 1)}"
    private_cidr = "${cidrsubnet(var.vpc_cidr, 6, 2)}"
}

resource "random_id" "kubernetes-cluster-tag" {
  byte_length = 16
}

resource "aws_subnet" "public" {
    count      = "${length(var.availability_zones)}"
    vpc_id     = "${aws_vpc.vpc.id}"
    cidr_block = "${cidrsubnet(local.public_cidr, 2, count.index)}"
    availability_zone = "${element(var.availability_zones, count.index)}"
    
    tags {
      Name = "${var.prefix}-cfcr-public-${count.index}"
      KubernetesCluster = "${random_id.kubernetes-cluster-tag.b64}"
    }
}

resource "aws_subnet" "private" {
    count      = "${length(var.availability_zones)}"
    vpc_id     = "${aws_vpc.vpc.id}"
    cidr_block = "${cidrsubnet(local.private_cidr, 2, count.index)}"
    availability_zone = "${element(var.availability_zones, count.index)}"

    tags {
      Name = "${var.prefix}-cfcr-private-${count.index}"
      KubernetesCluster = "${random_id.kubernetes-cluster-tag.b64}"
    }
}