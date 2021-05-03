KEY_NAME="ec2-key-`date +"%s"`"
KEY_PEM="$KEY_NAME.pem"

echo "Creating ec2 key and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME | jq -r ".KeyMaterial" > $KEY_PEM

echo "Setting access permissions of key file"
chmod 400 $KEY_PEM

echo "Creating security group for the instance"
SECURITY_GROUP="sec-grp-`date +'%N'`"
aws ec2 create-security-group --group-name $SECURITY_GROUP --description "Access my instances"


# Save my local ip address
LOCAL_IP=$(curl ipinfo.io/ip)


echo "Authorize rule with SSH access on port 22 to my local ip only"
aws ec2 authorize-security-group-ingress --group-name $SECURITY_GROUP --port 22 --protocol tcp --cidr $LOCAL_IP/32

echo "Authorize rule with HTTP access on port 80 to all (web)"
aws ec2 authorize-security-group-ingress --group-name $SECURITY_GROUP --port 80 --protocol tcp --cidr 0.0.0.0/0

echo "Creating Ubuntu 18.04 instance and waiting for its creation..."
UBUNTU_AMI="ami-06fd78dc2f0b69910"
RUN_INSTANCES=$(aws ec2 run-instances --image-id $UBUNTU_AMI --instance-type t3.micro --key-name $KEY_NAME --security-groups $SECURITY_GROUP)

INSTANCE_ID=$(echo $RUN_INSTANCES | jq -r '.Instances[0].InstanceId')
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

PUBLIC_DNS=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID | jq -r '.Reservations[0].Instances[0].PublicDnsName')

echo "New instance created"
echo "Instance ID: $INSTANCE_ID"
echo "Public DNS: $PUBLIC_DNS"

echo "Creating aws enviornment and waiting for instance status to be ok"

REGION=`cat ~/.aws/config | grep "region" | sed -n 's/\(region = \)\(.*\)/\2/p'`
KEY_ID=`cat ~/.aws/credentials | grep "aws_access_key_id" | sed -n 's/\(aws_access_key_id = \)\(.*\)/\2/p'`
KEY_SECRET=`cat ~/.aws/credentials | grep "aws_secret_access_key" | sed -n 's/\(aws_secret_access_key = \)\(.*\)/\2/p'`
echo "AWS_DEFAULT_REGION=${REGION}" >> aws_env_file
echo "AWS_ACCESS_KEY_ID=${KEY_ID}" >> aws_env_file
echo "AWS_SECRET_ACCESS_KEY=${KEY_SECRET}" >> aws_env_file

# Reboot instance and wait for it to run
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID

# Copying enviornment file to instance
echo "Copying env file"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" aws_env_file ubuntu@$PUBLIC_DNS:/home/ubuntu/
echo "Copied env file"
rm aws_env_file

echo "Setting up the production server"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_DNS <<EOF
    sudo apt update
    sudo apt install git -y
    sudo chmod 777 /etc/ssh/ssh_config
    echo "Setting server alive settings"
    sudo echo "    ServerAliveInterval 120" >> /etc/ssh/ssh_config
    sudo echo "    ServerAliveCountMax 5" >> /etc/ssh/ssh_config
    sudo echo "    TCPKeepAlive yes" >> /etc/ssh/ssh_config
    sudo chmod 777 /etc/ssh/sshd_config
    sudo echo "ClientAliveInterval 600" >> /etc/ssh/sshd_config
    sudo /etc/init.d/ssh restart
    echo "Cloning git repo..."
    sudo git clone https://github.com/nadav01/aws-parking-lot.git
    echo "Installing docker"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    cd aws-parking-lot
    echo "Building project using docker and run it"
    sudo docker build -t aws-parking-lot .
    sudo docker run --env-file ~/aws_env_file -p 80:80 aws-parking-lot
EOF
