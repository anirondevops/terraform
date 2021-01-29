##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}
variable "key_name" {}
variable "region" {
  default = "us-east-1"
}

variable "cidrRange" {
  default = {
    WebA = 0,
    AppA = 1,
    DbA = 2,
    WebB = 3,
    AppB = 4,
    DbB = 5,
    WebC = 6,
    AppC = 7,
    DbC = 8
  }
}

variable "SubnetA" {
  type = map(string)
  default = {
    WebA = "10.16.0.0/20"
    AppA = "10.16.16.0/20"
    DbA = "10.16.32.0/20"
  }
}

variable "SubnetB" {
  type = map(string)
  default = {
    WebB = "10.16.48.0/20"
    AppB = "10.16.64.0/20"
    DbB = "10.16.80.0/20"
  }
}

variable "SubnetC" {
  type = map(string)
  default = {
    WebC = "10.16.96.0/20"
    AppC = "10.16.112.0/20"
    DbC = "10.16.128.0/20"
  }
}

variable "web" {
  type = list(string)
  default = [ "WebA","WebB","WebC" ]
}

variable "azs" {
  type = list(string)
  default = ["A","B","C"]
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}


########################################################################################
# RESOURCES
########################################################################################

resource "aws_vpc" "custom_vpc" {
  cidr_block       = "10.16.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  assign_generated_ipv6_cidr_block = true
  tags = {
    Name = "ScubaSyndrome"
  }
}

# default security group
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.custom_vpc.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Availability Azone us-east-1a
resource "aws_subnet" "subnetA" {
  for_each = var.SubnetA
  availability_zone = "us-east-1a"
  vpc_id     = aws_vpc.custom_vpc.id
  cidr_block = each.value
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.custom_vpc.ipv6_cidr_block, 8, var.cidrRange["${each.key}"])}"
  map_public_ip_on_launch = true
  tags = {
    Name = each.key
  }
}

resource "aws_subnet" "subnetB" {
  for_each = var.SubnetB
  availability_zone = "us-east-1b"
  vpc_id     = aws_vpc.custom_vpc.id
  cidr_block = each.value
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.custom_vpc.ipv6_cidr_block, 8, var.cidrRange["${each.key}"])}"
  map_public_ip_on_launch = true
  tags = {
    Name = each.key
  }
}

resource "aws_subnet" "subnetC" {
  for_each = var.SubnetC
  availability_zone = "us-east-1c"
  vpc_id     = aws_vpc.custom_vpc.id
  cidr_block = each.value
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.custom_vpc.ipv6_cidr_block, 8, var.cidrRange["${each.key}"])}"
  map_public_ip_on_launch = true
  tags = {
    Name = each.key
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "SSIGW"
  }
}

# Public Route Table
resource "aws_route_table" "publicRouteTable" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "SSPublicRouteTable"
  }
}

# Public Route Table Subnet Association - Web Apps
# Associating public subnets to public route table
resource "aws_route_table_association" "publicRouteAssociationA" {
  subnet_id      = aws_subnet.subnetA["WebA"].id
  route_table_id = aws_route_table.publicRouteTable.id
}

resource "aws_route_table_association" "publicRouteAssociationC" {
  subnet_id      = aws_subnet.subnetC["WebC"].id
  route_table_id = aws_route_table.publicRouteTable.id
}
resource "aws_route_table_association" "publicRouteAssociationB" {
  subnet_id      = aws_subnet.subnetB["WebB"].id
  route_table_id = aws_route_table.publicRouteTable.id
}

# data for aws ami used for bastion host
data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]
    filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SECURITY GROUPS #
# For Bastion Host #
resource "aws_security_group" "bastionHostSG" {
  name   = "bastionHostSG"
  vpc_id = aws_vpc.custom_vpc.id

  #Allow HTTP from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastionHostSG"
  }

}

# creating a bastion host using ec2 instance - Web B Subnet
resource "aws_instance" "bastionHostEc2" {
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnetB["WebB"].id
  vpc_security_group_ids = [aws_security_group.bastionHostSG.id]
  key_name               = var.key_name

  tags = {
    Name = "BastionHostEc2"
  }
}

# Private EC2 instance - Subnet AppB
resource "aws_instance" "privateEc2AppB" {
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnetB["AppB"].id
  vpc_security_group_ids = [aws_default_security_group.default.id]
  key_name               = var.key_name

  tags = {
    Name = "PrivateInstanceAppB"
  }
}

# eip for the nat gateways
resource "aws_eip" "eip_nat_gateway" {
  for_each = toset(var.web)
  vpc = true
}

# NAT Gateways - 3 to sit in public subnets - WebA,B and C
resource "aws_nat_gateway" "natA" {
  allocation_id = aws_eip.eip_nat_gateway["WebA"].id
  subnet_id     = aws_subnet.subnetA["WebA"].id
  tags = {
    Name = "NatGateWay - WebA"
  }
}

resource "aws_nat_gateway" "natB" {
  allocation_id = aws_eip.eip_nat_gateway["WebB"].id
  subnet_id     = aws_subnet.subnetB["WebB"].id
  tags = {
    Name = "NatGateWay - WebB"
  }
}

resource "aws_nat_gateway" "natC" {
  allocation_id = aws_eip.eip_nat_gateway["WebC"].id
  subnet_id     = aws_subnet.subnetC["WebC"].id
  tags = {
    Name = "NatGateWay - WebC"
  }
}

# Private Route Tables for each AZ - A,B,C

resource "aws_route_table" "privateRouteTableA" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natA.id
  }
  tags = {
    Name = "PrivateRT-A"
  }

  depends_on = [ aws_nat_gateway.natA]
}

resource "aws_route_table" "privateRouteTableB" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natB.id
  }
  tags = {
    Name = "PrivateRT-B"
  }

  depends_on = [ aws_nat_gateway.natB]
}

resource "aws_route_table" "privateRouteTableC" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natC.id
  }
  tags = {
    Name = "PrivateRT-C"
  }

  depends_on = [ aws_nat_gateway.natC]
}

# subnet associations App & Db - to private route table WebA,WebB,WebC
resource "aws_route_table_association" "associationA" {
  for_each = toset([ "AppA","DbA" ])
  subnet_id      = aws_subnet.subnetA["${each.key}"].id
  route_table_id = aws_route_table.privateRouteTableA.id
}

resource "aws_route_table_association" "associationB" {
  for_each = toset([ "AppB","DbB" ])
  subnet_id      = aws_subnet.subnetB["${each.key}"].id
  route_table_id = aws_route_table.privateRouteTableB.id
}

resource "aws_route_table_association" "associationC" {
  for_each = toset([ "AppC","DbC" ])
  subnet_id      = aws_subnet.subnetC["${each.key}"].id
  route_table_id = aws_route_table.privateRouteTableC.id
}

# Egress Only Internet Gateway
resource "aws_egress_only_internet_gateway" "egress" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "EgressOnlyIgw"
  }
}

# Add egress route for the private instance in subnet b. Update Private Route Table - B
resource "aws_route" "addrouteb" {
  route_table_id              = aws_route_table.privateRouteTableB.id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.egress.id
}