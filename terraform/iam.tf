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
                "sts:DecodeAuthorizationMessage",
                "ec2:RequestSpotInstances",
                "ec2:DescribeSpotInstanceRequests",
                "ec2:CancelSpotInstanceRequests",
                "iam:CreateServiceLinkedRole"
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