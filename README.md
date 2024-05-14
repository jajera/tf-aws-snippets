# tf-aws-snippets

# Delete all .terraform directories
find . -type d -name ".terraform" -exec rm -rf {} +

# Delete all terraform.tfstate and terraform.tfstate.backup files
find . -type f -name "terraform.tfstate*" -exec rm -f {} +

# Delete all .terraform.lock.hcl files
find . -type f -name ".terraform.lock.hcl" -exec rm -f {} +

# Delete all provider cache directories
find . -type d -name ".terraform-provider-cache" -exec rm -rf {} +
