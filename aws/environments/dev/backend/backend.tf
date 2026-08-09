terraform {
  # Narrow bootstrap exception: this root must create the S3 backend before it
  # can be migrated. No infrastructure-consuming root may use local state.
  backend "local" {
    path = "terraform.tfstate"
  }
}
