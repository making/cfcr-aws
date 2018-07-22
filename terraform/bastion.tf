resource "aws_key_pair" "deployer" {
  key_name   = "${var.prefix}-deployer"
  public_key = "${tls_private_key.deployer.public_key_openssh}"
}

resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = "4096"
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
        "export default_security_groups=${aws_security_group.vms_security_group.id}",
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