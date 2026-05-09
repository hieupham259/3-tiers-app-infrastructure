variable "primary_domain" {
  type        = string
  description = "Primary domain (e.g. myapp.example.com)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
