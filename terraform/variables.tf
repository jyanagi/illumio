variable "pce_url" {
  default      = "https://illumio.acme.com:8443"
  description  = "URL of the Illumio Policy Compute Engine and Web Socket (i.e., https://illumio.acme.com:8443)"
}

variable "pce_org_id" {
  default      = "<REPLACE_WITH_ORG_ID>"
}

variable "pce_api_key" {
  default      = "<REPLACE_WITH_API_KEY>"
}

variable "pce_api_secret" {
  default      = "<REPLACE_WITH_API_TOKEN>"
}
