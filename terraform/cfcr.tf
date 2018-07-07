variable "region" {
    type = "string"
}

variable "access_key" {
    type = "string"
}

variable "secret_key" {
    type = "string"
}

variable "availability_zones" {
  type = "list"
}

variable "vpc_cidr" {
    type    = "string"
    default = "10.0.0.0/16"
}

variable "prefix" {
    type = "string"
    default = ""
}

variable "kubernetes_master_port" {
    type = "string"
    default = "8443"
}

variable "nat_instance_type" {
    default = "t2.micro"
}

variable "bastion_instance_type" {
    default = "t2.micro"
}

provider "aws" {
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
    region = "${var.region}"
}

locals {
    public_cidr  = "${cidrsubnet(var.vpc_cidr, 6, 1)}"
    private_cidr = "${cidrsubnet(var.vpc_cidr, 6, 2)}"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  tags {
    Name = "${var.prefix}-cfcr-vpc"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.prefix}-deployer"
  public_key = "${tls_private_key.deployer.public_key_openssh}"
}

resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "random_id" "kubernetes-cluster-tag" {
  byte_length = 16
}

resource "aws_internet_gateway" "gateway" {
    vpc_id = "${aws_vpc.vpc.id}"
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

resource "aws_route_table" "public" {
    vpc_id = "${aws_vpc.vpc.id}"

    tags {
      Name = "${var.prefix}-public-route-table"
    }

    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.gateway.id}"
    }
}

resource "aws_route_table_association" "public" {
    count          = "${length(var.availability_zones)}"
    subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
    route_table_id = "${aws_route_table.public.id}"
}

variable "nat_ami_map" {
    type = "map"

    default = {
      us-east-1      = "ami-303b1458"
      us-east-2      = "ami-4e8fa32b"
      us-west-1      = "ami-7da94839"
      us-west-2      = "ami-69ae8259"
      eu-west-1      = "ami-6975eb1e"
      eu-central-1   = "ami-46073a5b"
      ap-southeast-1 = "ami-b49dace6"
      ap-southeast-2 = "ami-e7ee9edd"
      ap-northeast-1 = "ami-03cf3903"
      ap-northeast-2 = "ami-8e0fa6e0"
      sa-east-1      = "ami-fbfa41e6"
    }
}

resource "aws_instance" "nat" {
    ami                    = "${lookup(var.nat_ami_map, var.region)}"
    instance_type          = "${var.nat_instance_type}"
    vpc_security_group_ids = ["${aws_security_group.nat.id}"]
    source_dest_check      = false
    subnet_id              = "${aws_subnet.public.0.id}"
    associate_public_ip_address = true

    tags {
      Name = "${var.prefix}-nat"
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

resource "aws_route_table" "private" {
    count  = "${length(var.availability_zones)}"
    vpc_id = "${aws_vpc.vpc.id}"

    tags {
      Name = "${var.prefix}-private-route-table"
    }

    route {
      cidr_block = "0.0.0.0/0"
      instance_id = "${aws_instance.nat.id}"
    }
}

resource "aws_route_table_association" "private" {
    count          = "${length(var.availability_zones)}"
    subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
    route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
}

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

resource "aws_elb" "api" {
    name               = "${var.prefix}-cfcr-api"
    subnets = ["${aws_subnet.public.*.id}"]
    security_groups = ["${aws_security_group.api.id}"]

    listener {
      instance_port      = "${var.kubernetes_master_port}"
      instance_protocol  = "tcp"
      lb_port            = "${var.kubernetes_master_port}"
      lb_protocol        = "tcp"
    }

    health_check {
      healthy_threshold   = 6
      unhealthy_threshold = 3
      timeout             = 3
      target              = "TCP:${var.kubernetes_master_port}"
      interval            = 5
    }
}

data "aws_ami" "ubuntu" {
    most_recent = true

    filter {
      name   = "name"
      values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
    }

    filter {
      name   = "virtualization-type"
      values = ["hvm"]
    }

    owners = ["099720109477"] # Canonical
}

resource "aws_iam_role_policy" "cfcr-master" {
    name = "${var.prefix}-cfcr-master"
    role = "${aws_iam_role.cfcr-master.id}"

    policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
          "ec2:DescribeInstances",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes"
        ],
        "Resource": [
          "*"
        ]
      },
      {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
          "ec2:CreateTags",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DeleteVolume"
        ],
        "Resource": [
          "*"
        ]
      },
      {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
          "ec2:DescribeVpcs",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:AttachLoadBalancerToSubnets",
          "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancerPolicy",
          "elasticloadbalancing:CreateLoadBalancerListeners",
          "elasticloadbalancing:ConfigureHealthCheck",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancerListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DetachLoadBalancerFromSubnets",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancerPolicies",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:SetLoadBalancerPoliciesOfListener"
        ],
        "Resource": [
          "*"
        ]
      }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "cfcr-master" {
    name = "${var.prefix}-cfcr-master"
    role = "${aws_iam_role.cfcr-master.name}"
}

resource "aws_iam_role" "cfcr-master" {
    name = "${var.prefix}-cfcr-master"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cfcr-worker" {
    name = "${var.prefix}-cfcr-worker"
    role = "${aws_iam_role.cfcr-worker.id}"

    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "cfcr-worker" {
    name = "${var.prefix}-cfcr-worker"
    role = "${aws_iam_role.cfcr-worker.name}"
}

resource "aws_iam_role" "cfcr-worker" {
    name = "${var.prefix}-cfcr-worker"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role" "bosh-director" {
    name = "${var.prefix}-bosh-director"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "bosh-director" {
    name = "${var.prefix}-bosh-director"
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:AssociateAddress",
                "ec2:AttachVolume",
                "ec2:CreateVolume",
                "ec2:DeleteSnapshot",
                "ec2:DeleteVolume",
                "ec2:DescribeAddresses",
                "ec2:DescribeImages",
                "ec2:DescribeInstances",
                "ec2:DescribeRegions",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSnapshots",
                "ec2:DescribeSubnets",
                "ec2:DescribeVolumes",
                "ec2:DetachVolume",
                "ec2:CreateSnapshot",
                "ec2:CreateTags",
                "ec2:RunInstances",
                "ec2:TerminateInstances",
                "ec2:RegisterImage",
                "ec2:DeregisterImage",
                "elasticloadbalancing:*",
                "sts:DecodeAuthorizationMessage"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Action": [
                "iam:PassRole"
            ],
            "Effect": "Allow",
            "Resource": "${aws_iam_role.cfcr-master.arn}"
        },
        {
            "Action": [
                "iam:PassRole"
            ],
            "Effect": "Allow",
            "Resource": "${aws_iam_role.cfcr-worker.arn}"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "bosh-director" {
  role       = "${var.prefix}-bosh-director"
  policy_arn = "${aws_iam_policy.bosh-director.arn}"
}

resource "aws_iam_user" "bosh-director" {
  name = "${var.prefix}-bosh-director"
}

resource "aws_iam_access_key" "bosh-director" {
  user = "${aws_iam_user.bosh-director.name}"
}

resource "aws_iam_user_policy_attachment" "bosh-director" {
  user       = "${aws_iam_user.bosh-director.name}"
  policy_arn = "${aws_iam_policy.bosh-director.arn}"
}

resource "aws_instance" "bastion" {
    ami           = "${data.aws_ami.ubuntu.id}"
    instance_type = "${var.bastion_instance_type}"
    subnet_id     = "${aws_subnet.public.0.id}"
    availability_zone = "${var.availability_zones[0]}"
    key_name      = "${aws_key_pair.deployer.key_name}"
    vpc_security_group_ids = ["${aws_security_group.nodes.id}"]
    associate_public_ip_address = true

    tags {
      Name = "${var.prefix}-bosh-bastion"
    }

    provisioner "remote-exec" {
      inline = [
        "set -eu",
        "sudo apt-get update",
        "sudo apt-get install -y build-essential zlibc zlib1g-dev ruby ruby-dev openssl libxslt-dev libxml2-dev libssl-dev libreadline6 libreadline6-dev libyaml-dev libsqlite3-dev sqlite3 jq awscli",
        "sudo apt-get install -y git",
        "sudo apt-get install -y unzip",
        "curl -L https://github.com/cloudfoundry-incubator/credhub-cli/releases/download/1.7.5/credhub-linux-1.7.5.tgz | tar zxv && sudo chmod a+x credhub && sudo mv credhub /usr/bin",
        "sudo curl -L https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl -o /usr/bin/kubectl && sudo chmod a+x /usr/bin/kubectl",
        "sudo curl https://s3.amazonaws.com/bosh-cli-artifacts/bosh-cli-3.0.1-linux-amd64 -o /usr/bin/bosh && sudo chmod a+x /usr/bin/bosh && sudo ln -s /usr/bin/bosh /usr/bin/bosh-cli",
        "sudo wget https://releases.hashicorp.com/terraform/0.11.7/terraform_0.11.7_linux_amd64.zip",
        "sudo unzip terraform*.zip -d /usr/local/bin",
        "sudo sh -c 'sudo cat > /etc/profile.d/bosh.sh <<'EOF'",
        "#!/bin/bash",
        "export private_subnet_ids=${join(",",aws_subnet.private.*.id)}",
        "export public_subnet_ids=${join(",",aws_subnet.public.*.id)}",
        "export private_subnet_cidr_blocks=${join(",",aws_subnet.private.*.cidr_block)}",
        "export public_subnet_cidr_blocks=${join(",",aws_subnet.public.*.cidr_block)}",
        "export public_subnet_ids=${join(",",aws_subnet.public.*.id)}",
        "export vpc_cidr=${var.vpc_cidr}",
        "export vpc_id=${aws_vpc.vpc.id}",
        "export default_security_groups=${aws_security_group.nodes.id}",
        "export prefix=${var.prefix}",
        "export default_key_name=${aws_key_pair.deployer.key_name}",
        "export region=${var.region}",
        "export availability_zones=${join(",", var.availability_zones)}",
        "export kubernetes_cluster_tag=${random_id.kubernetes-cluster-tag.b64}",
        "export master_lb_ip_address=${aws_elb.api.dns_name}",
        "export AWS_ACCESS_KEY_ID=${aws_iam_access_key.bosh-director.id}",
        "export AWS_SECRET_ACCESS_KEY=${aws_iam_access_key.bosh-director.secret}",
        "EOF'",
        "sudo mkdir /share",
        "sudo chown ubuntu:ubuntu /share",
        "echo \"${tls_private_key.deployer.private_key_pem}\" > /home/ubuntu/deployer.pem",
        "chmod 600 /home/ubuntu/deployer.pem"
      ]

      connection {
        type     = "ssh"
        user = "ubuntu"
        private_key = "${tls_private_key.deployer.private_key_pem}"
      }
    }

    provisioner "file" {
      source = "terraform.tfstate"
      destination = "/home/ubuntu/terraform.tfstate"

      connection {
        type     = "ssh"
        user = "ubuntu"
        private_key = "${tls_private_key.deployer.private_key_pem}"
      }
    }

    provisioner "file" {
      source = "terraform.tfvars"
      destination = "/home/ubuntu/terraform.tfvars"

      connection {
        type     = "ssh"
        user = "ubuntu"
        private_key = "${tls_private_key.deployer.private_key_pem}"
      }
    }
}

resource "aws_eip" "bastion" {
    instance = "${aws_instance.bastion.id}"
    vpc      = true
}

output "bosh_bastion_ip" {
    value = "${aws_eip.bastion.public_ip}"
}

output "cfcr_master_target_pool" {
   value = "${aws_elb.api.name}"
}

output "master_lb_ip_address" {
  value = "${aws_elb.api.dns_name}"
}