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

variable "lb_protocol" {
    type = "string"
    default = "tcp"
}

variable "use_alb" {
    default = false
}

variable "ssl_cert_arn" {
    type = "string"
    default = ""
}

variable "nat_instance_type" {
    default = "t2.micro"
}

variable "bastion_instance_type" {
    default = "t2.micro"
}
