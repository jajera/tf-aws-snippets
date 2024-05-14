resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "awscc_s3_bucket" "example" {
  bucket_name = "example-${random_string.suffix.result}"
  # versioning_configuration = {
  #   status = "Enabled"
  # }
  lifecycle_configuration = {
    rules = [
      {
        id = "infrequent_access_storage"

        noncurrent_version_transitions = [
          {
            transition_in_days = 30
            storage_class      = "STANDARD_IA"
          }
        ]
        status = "Enabled"
      }
    ]
  }
}
