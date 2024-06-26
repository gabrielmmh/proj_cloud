#!/bin/bash

# Define the bucket name, region, and secret name
CODEPIPELINE_BUCKET_NAME="gabrielmmh-codepipeline-bucket"
REGION="us-east-1"
SECRET_NAME="gabriel-access-token"
STACK_NAME="gabrielmmhStack3"

# Check and install AWS CLI if not installed
if ! command -v aws &> /dev/null; then
    echo -e "AWS CLI not found, installing...\n"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
else
    echo -e "AWS CLI is already installed.\n"
fi

# Check and install jq if not installed
if ! command -v jq &> /dev/null; then
    echo -e "jq not found, installing...\n"
    sudo apt-get install jq -y
else
    echo -e "jq is already installed.\n"
fi

# Check and install git if not installed
if ! command -v git &> /dev/null; then
    echo -e "git not found, installing...\n"
    sudo apt-get install git -y
else
    echo -e "git is already installed.\n"
fi

# Function to prompt user for GitHub credentials and verify them
function get_github_credentials() {
    while true; do
        read -p "Enter your GitHub username: " GITHUB_USERNAME
        read -s -p "Enter your GitHub token: " GITHUB_TOKEN
        echo

        # Verify GitHub credentials
        response=$(curl -u "$GITHUB_USERNAME:$GITHUB_TOKEN" -s https://api.github.com/user)
        if echo "$response" | grep -q "\"login\": \"$GITHUB_USERNAME\""; then
            echo -e "\nGitHub credentials verified successfully.\n"
            break
        else
            echo "\nInvalid GitHub credentials. Please try again.\n"
        fi
    done
}

# Create secret.json with GitHub credentials
function create_secret_json() {
    cat <<EOF > secret.json
{
  "username": "$GITHUB_USERNAME",
  "token": "$GITHUB_TOKEN"
}
EOF
}

# Function to check if GitHub repository exists
function github_repo_exists() {
    local repo_name=$1
    response=$(curl -s -u "$GITHUB_USERNAME:$GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_USERNAME/$repo_name")
    if echo "$response" | grep -q "\"full_name\": \"$GITHUB_USERNAME/$repo_name\""; then
        return 0
    else
        return 1
    fi
}

# Function to create GitHub repository
function create_github_repo() {
    local repo_name=$1
    response=$(curl -u "$GITHUB_USERNAME:$GITHUB_TOKEN" -s https://api.github.com/user/repos -d "{\"name\":\"$repo_name\"}")
    if echo "$response" | grep -q "\"full_name\": \"$GITHUB_USERNAME/$repo_name\""; then
        echo -e "Repository $repo_name created.\n"
        return 0
    else
        echo -e "Failed to create repository $repo_name. Response: $response\n"
        return 1
    fi
}

# Function to push code to GitHub repository
function push_to_github_repo() {
    local repo_name=$1
    local repo_dir=$2
    cd $repo_dir
    git init
    git config user.email "$GITHUB_EMAIL"
    git config user.name "$GITHUB_USERNAME"
    git remote add origin "https://github.com/$GITHUB_USERNAME/$repo_name.git"
    git add .
    git commit -m "Initial commit"
    git branch -M main  # Rename branch to main
    git push -u origin main
    cd -
}

# Check if secret.json already exists
if [ -f secret.json ]; then
    echo "secret.json already exists."
    GITHUB_USERNAME=$(jq -r .username secret.json)
    GITHUB_TOKEN=$(jq -r .token secret.json)
    GITHUB_EMAIL=$(jq -r .email secret.json)
else
    # Get GitHub credentials from the user
    get_github_credentials
    read -p "Enter your GitHub email: " GITHUB_EMAIL

    # Create secret.json
    create_secret_json
fi

# Check if GitHub repositories exist and prompt user if they don't
REPOS_EXIST=true

if ! github_repo_exists "proj_app_cloud" || ! github_repo_exists "proj_infra_cloud"; then
    REPOS_EXIST=false
    read -p "Do you allow the script to create GitHub repositories proj_app_cloud and proj_infra_cloud in your GitHub Account? (y/N): " create_repos
    if [[ $create_repos != "y" && $create_repos != "Y" ]]; then
        echo -e "\nUser chose not to create repositories. Exiting.\n"
        exit 0
    fi
fi

# Create and push to GitHub repositories if they don't exist
if ! github_repo_exists "proj_app_cloud"; then
    create_github_repo "proj_app_cloud" && push_to_github_repo "proj_app_cloud" "./app"
else
    echo -e "Repository proj_app_cloud already exists. Skipping creation and push.\n"
fi

if ! github_repo_exists "proj_infra_cloud"; then
    create_github_repo "proj_infra_cloud" && push_to_github_repo "proj_infra_cloud" "./infra"
else
    echo -e "Repository proj_infra_cloud already exists. Skipping creation and push.\n"
fi

# Configure AWS CLI region
aws configure set region $REGION

# Clone the proj_infra_cloud repository into a specific subdirectory outside the current directory
if [ -d "../proj_infra_cloud_clone" ]; then
    echo -e "../proj_infra_cloud_clone directory already exists. Skipping clone.\n"
else
    echo -e "\nCloning the proj_infra_cloud repository into ../proj_infra_cloud_clone...\n"
    mkdir ../proj_infra_cloud_clone
    git clone https://github.com/$GITHUB_USERNAME/proj_infra_cloud.git ../proj_infra_cloud_clone
fi

# Create or update a secret in AWS Secrets Manager
echo -e "\nCreating a secret in AWS Secrets Manager...\n"
aws secretsmanager create-secret --name $SECRET_NAME --secret-string file://secret.json || echo "Secret already exists, skipping creation..."

# Validate CloudFormation Templates
echo -e "\nValidating CloudFormation templates locally...\n"
aws cloudformation validate-template --template-body file://codepipeline.yaml

echo -e "\nGetting the ARN of the secret...\n"
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id $SECRET_NAME --query ARN --output text)

# Create or update CloudFormation Stack using local template
echo -e "\nCreating or updating CloudFormation stack using local template...\n"

aws cloudformation deploy --template-file ./codepipeline.yaml --stack-name $STACK_NAME --capabilities CAPABILITY_NAMED_IAM --parameter-overrides SecretARN=$SECRET_ARN MyStackName=$STACK_NAME
# Wait for stack operation to complete
echo -e "\nWaiting for stack operation to complete...\n"
if aws cloudformation describe-stacks --stack-name $STACK_NAME > /dev/null 2>&1; then
    aws cloudformation wait stack-update-complete --stack-name $STACK_NAME
else
    aws cloudformation wait stack-create-complete --stack-name $STACK_NAME
fi

LOAD_BALANCER_DNS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDNS'].OutputValue" --output text)

# Verify if the ALB DNS is reachable
if [ -z "$LOAD_BALANCER_DNS" ]; then
    echo -e "\nALB DNS' unreachable.\n"
    exit 1
else
    # Create the documentation link
    DOCUMENTATION_LINK="http://$LOAD_BALANCER_DNS/docs"

    # Echo the documentation link
    echo -e "\nAccess in: \e]8;;$DOCUMENTATION_LINK\a$DOCUMENTATION_LINK\e]8;;\a\n"
fi

echo -e "\nDeployment script executed successfully.\n"