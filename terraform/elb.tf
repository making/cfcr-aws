resource "aws_elb" "api" {
    name               = "${var.prefix}-cfcr-api"
    subnets = ["${aws_subnet.public.*.id}"]
    security_groups = ["${aws_security_group.api.id}"]
    count = "${var.use_alb ? 0 : 1}"

    listener {
      instance_port      = "8443"
      instance_protocol  = "${var.lb_protocol}"
      lb_port            = "${var.kubernetes_master_port}"
      lb_protocol        = "${var.lb_protocol}"
      ssl_certificate_id = "${var.ssl_cert_arn}"
    }

    health_check {
      healthy_threshold   = 6
      unhealthy_threshold = 3
      timeout             = 3
      target              = "TCP:8443"
      interval            = 5
    }
}