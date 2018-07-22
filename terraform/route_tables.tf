resource "aws_internet_gateway" "gateway" {
    vpc_id = "${aws_vpc.vpc.id}"
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