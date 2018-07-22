resource "aws_elb" "api" {
    name               = "${var.prefix}-cfcr-api"
    subnets = ["${aws_subnet.public.*.id}"]
    security_groups = ["${aws_security_group.api.id}"]

    listener {
      instance_port      = "8443"
      instance_protocol  = "${var.lb_protocol}"
      lb_port            = "${var.kubernetes_master_port}"
      lb_protocol        = "${var.lb_protocol}"
      ssl_certificate_id = "${var.ssl_certificate_id}"
    }

    health_check {
      healthy_threshold   = 6
      unhealthy_threshold = 3
      timeout             = 3
      target              = "TCP:8443"
      interval            = 5
    }
}