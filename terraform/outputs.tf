output "bosh_bastion_ip" {
   value = "${aws_eip.bastion.public_ip}"
}

output "cfcr_master_target_pool" {
   value = "${aws_elb.api.*.name}"
}

output "master_lb_ip_address" {
   value = "${aws_elb.api.*.dns_name}"
}

output "front_end_lb_name" {
  value = "${aws_lb.front_end.*.name}"
}

output "front_end_lb_dns_name" {
  value = "${aws_lb.front_end.*.dns_name}"
}

output "api_target_group_name" {
  value = "${aws_lb_target_group.cfcr_api.*.name}"
}