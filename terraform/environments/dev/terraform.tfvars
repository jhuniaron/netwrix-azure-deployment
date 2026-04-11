# Non-sensitive values only — sensitive vars come from TF_VAR_* env vars set in the pipeline
subscription_id     = "69a76f8c-1ff3-4ff8-9ffe-4b77b1d0273e"
project             = "netwrix"
environment         = "dev"
location            = "australiaeast"
app_service_sku     = "B2"  # P1v3 has 0 quota on this subscription; B2 (Standard) is equivalent for dev
aad_admin_login     = "Jhun  Iaron Fedelino"
aad_admin_object_id = "0e1641cc-f8b6-415e-8199-bd8b2f649c51"
alert_email         = "jhuniaron.fedelino@gmail.com"
