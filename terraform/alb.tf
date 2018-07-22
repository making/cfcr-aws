resource "aws_lb" "front_end" {
  name            = "${var.prefix}-front-end"
  subnets         = ["${aws_subnet.public.*.id}"]
  security_groups = ["${aws_security_group.api.id}"]
  count           = "${var.use_alb ? 1 : 0}"
}

resource "aws_lb_target_group" "cfcr_api" {
  name     = "${var.prefix}-cfcr-api"
  port     = "8443"
  protocol = "HTTPS"
  vpc_id   = "${aws_vpc.vpc.id}"
  count    = "${var.use_alb ? 1 : 0}"
  health_check {
    protocol = "HTTPS"
    path = "/healthz"
    port = 8443
    matcher = "200"    
    healthy_threshold   = 6
    unhealthy_threshold = 3
    timeout             = 3
    interval            = 5
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = "${aws_lb.front_end.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2015-05"
  certificate_arn   = "${var.ssl_cert_arn}"
  count             = "${var.use_alb ? 1 : 0}"

  default_action {
    target_group_arn = "${aws_lb_target_group.cfcr_api.arn}"
    type             = "forward"
  }
}