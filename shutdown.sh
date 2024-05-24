#!/bin/bash

# Define the bucket names, CloudFormation stack name, and secret name
CODEPIPELINE_BUCKET_NAME="gabrielmmh-codepipeline-bucket2"
STACK_NAME="gabrielmmhStack3"
SECRET_NAME="github-access-token"

# Function to delete a GitHub repository
function delete_github_repo() {
    local repo_name=$1
    local response=$(curl -s -u "$GITHUB_USERNAME:$GITHUB_TOKEN" -X DELETE "https://api.github.com/repos/$GITHUB_USERNAME/$repo_name")
    if [[ $response == "" ]]; then
        echo "Repository $repo_name deleted successfully."
    else
        echo "Failed to delete repository $repo_name. Response: $response"
    fi
}

# Retrieve GitHub credentials from AWS Secrets Manager
echo -e "\nRetrieving GitHub credentials from AWS Secrets Manager...\n"
GITHUB_CREDENTIALS=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text)
GITHUB_USERNAME=$(echo $GITHUB_CREDENTIALS | jq -r .username)
GITHUB_TOKEN=$(echo $GITHUB_CREDENTIALS | jq -r .token)

# Remove the proj_infra_cloud_clone directory
if [ -d "../proj_infra_cloud_clone" ]; then
    echo -e "\nRemoving the ../proj_infra_cloud_clone directory...\n"
    rm -rf ../proj_infra_cloud_clone
fi

# Delete GitHub repositories
echo -e "\nDeleting GitHub repositories...\n"
delete_github_repo "proj_app_cloud"
delete_github_repo "proj_infra_cloud"

# Empty the infrastructure S3 bucket
echo -e "\nEmptying the infrastructure S3 bucket...\n"
aws s3 rm s3://$CODEPIPELINE_BUCKET_NAME --recursive
echo -e "\nInfrastructure S3 bucket emptied.\n"

# Deleting CloudFormation stack
echo -e "\nDeleting CloudFormation stack...\n"
aws cloudformation delete-stack --stack-name $STACK_NAME

echo -e "\nWaiting for stack to be deleted...\n"
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
echo -e "\nCloudFormation stack deleted.\n"

# Delete the AWS Secrets Manager secret
echo -e "\nDeleting the AWS secret...\n"
aws secretsmanager delete-secret --secret-id $SECRET_NAME --force-delete-without-recovery
echo -e "\nAWS secret deleted.\n"

echo -e "Shutdown script executed successfully."