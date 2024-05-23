#!/bin/bash

# Define the name of your CloudFormation stack
STACK_NAME="gabrielmmhStack3"

# Get the DNS of the Load Balancer using AWS CLI
LOAD_BALANCER_DNS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDNS'].OutputValue" --output text)

# Check if the DNS was retrieved successfully
if [ -z "$LOAD_BALANCER_DNS" ]; then
    echo "Failed to retrieve the Load Balancer DNS."
    exit 1
else
    echo "Load Balancer DNS retrieved: $LOAD_BALANCER_DNS"
fi

# Check if locust is installed, if not, install it
if ! command -v locust &> /dev/null; then
    echo "Locust not found, installing..."
    pip install locust
else
    echo "Locust is already installed."
fi

# Change to the directory where locustfile.py is located
cd locust

# Check if locustfile.py exists in the directory
if [ ! -f locustfile.py ]; then
    echo "locustfile.py not found in the locust directory."
    exit 1
fi

# This will start Locust in web mode
locust --host=http://$LOAD_BALANCER_DNS --web-host localhost -u 100 -r 10