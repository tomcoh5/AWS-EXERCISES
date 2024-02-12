#!/bin/bash

# Define variables
region="Us East(N. Virginia)"
vpc_id="vpc-0dcc3d36e9a04ad0e"
subnet_id_1="subnet-00253132bf48ea8a0"
subnet_id_2="subnet-0c09d4a8b32f2e040"
random_string=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 10)
security_group_name="launch-wizard-$random_string"
alb_name="my-alb-$random_string"
target_group_name_red="target-group-red"
target_group_name_blue="target-group-blue"

ami_id=$(aws ec2 describe-images     --region us-east-1     --owners amazon     --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2"     --query 'Images | [0].ImageId'     --output text)
# Task 1: Create Security Group
echo "Creating security group..."
security_group_id=$(aws ec2 create-security-group --group-name $security_group_name --description "Security group for EC2 instances" --vpc-id $vpc_id --output text)
aws ec2 authorize-security-group-ingress --group-id $security_group_id --protocol tcp --port 80 --cidr 0.0.0.0/0

# Task 2: Create Application Load Balancer (ALB)
echo "Creating Application Load Balancer..."
alb_arn=$(aws elbv2 create-load-balancer --name $alb_name --subnets $subnet_id_1 $subnet_id_2 --security-groups $security_group_id --output text --query "LoadBalancers[0].LoadBalancerArn")

# Task 3: Create Target Groups
echo "Creating target groups..."
target_group_arn_red=$(aws elbv2 create-target-group --name $target_group_name_red --protocol HTTP --port 80 --vpc-id $vpc_id --output text --query "TargetGroups[0].TargetGroupArn")
target_group_arn_blue=$(aws elbv2 create-target-group --name $target_group_name_blue --protocol HTTP --port 80 --vpc-id $vpc_id --output text --query "TargetGroups[0].TargetGroupArn")

# Task 4: Launch EC2 Instances
echo "Launching EC2 instances..."
instance_id_red=$(aws ec2 run-instances --image-id $ami_id --count 1 --instance-type t2.micro --security-group-ids $security_group_id --subnet-id $subnet_id_1 --user-data "#!/bin/bash
yum update -y
yum install httpd -y
echo '<html><body><h1 style=\"color:red\">This is the RED instance</h1></body></html>' > /var/www/html/index.html
systemctl start httpd" | jq -r '.Instances[0].InstanceId')

instance_id_blue=$(aws ec2 run-instances --image-id $ami_id --count 1 --instance-type t2.micro --security-group-ids $security_group_id --subnet-id $subnet_id_2 --user-data "#!/bin/bash
yum update -y
yum install httpd -y
echo '<html><body><h1 style=\"color:blue\">This is the BLUE instance</h1></body></html>' > /var/www/html/index.html
systemctl start httpd" | jq -r '.Instances[0].InstanceId')

echo "sleeping for 60 seconds waiting for instance to run"
sleep 60
# Task 5: Register Targets with Target Groups
echo "Registering targets with target groups..."
aws elbv2 register-targets --target-group-arn $target_group_arn_red --targets Id=$instance_id_red
aws elbv2 register-targets --target-group-arn $target_group_arn_blue --targets Id=$instance_id_blue

# Task 6: Create Listeners
echo "Creating listeners..."
aws elbv2 create-listener --load-balancer-arn $alb_arn --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$target_group_arn_red --output text
aws elbv2 create-listener --load-balancer-arn $alb_arn --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$target_group_arn_blue --output text

echo "Deployment complete
