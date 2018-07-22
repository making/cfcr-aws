resource "aws_security_group" "nodes" {
    name        = "${var.prefix}-node-access"
    vpc_id      = "${aws_vpc.vpc.id}"
}

resource "aws_security_group" "nat" {
    name        = "${var.prefix}-nat-access"
    description = "NAT Security Group"
    vpc_id      = "${aws_vpc.vpc.id}"

    ingress {
      cidr_blocks = ["${var.vpc_cidr}"]
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
    }

    egress {
      cidr_blocks = ["0.0.0.0/0"]
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
    }
}

resource "aws_security_group" "vms_security_group" {
  name        = "${var.prefix}-bosh-vms"
  description = "VMs Security Group"
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress {
    cidr_blocks = ["${var.vpc_cidr}"]
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }
}

resource "aws_security_group_rule" "outbound" {
    type            = "egress"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]

    security_group_id = "${aws_security_group.nodes.id}"
}

resource "aws_security_group_rule" "UAA" {
    type        = "ingress"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

    security_group_id = "${aws_security_group.nodes.id}"
}

resource "aws_security_group_rule" "ssh" {
    type            = "ingress"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]

    security_group_id = "${aws_security_group.nodes.id}"
}

resource "aws_security_group_rule" "node-to-node" {
    type            = "ingress"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    source_security_group_id = "${aws_security_group.nodes.id}"

    security_group_id = "${aws_security_group.nodes.id}"
}

resource "aws_security_group" "api" {
    name        = "${var.prefix}-api-access"
    vpc_id      = "${aws_vpc.vpc.id}"

    ingress {
      from_port   = "${var.kubernetes_master_port}"
      to_port     = "${var.kubernetes_master_port}"
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      cidr_blocks     = ["0.0.0.0/0"]
    }
}