output "bosh_bastion_ip" {
    value = "${aws_eip.bastion.public_ip}"
}

output "cfcr_master_target_pool" {
   value = "${aws_elb.api.name}"
}

output "master_lb_ip_address" {
  value = "${aws_elb.api.dns_name}"
}