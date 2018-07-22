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