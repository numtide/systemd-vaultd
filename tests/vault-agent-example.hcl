 vault = {
   address = "http://localhost:8200"
 }
 template = {
   contents = "{{ with secret \"secret/my-secret\" }}{{ .Data.data.foo }}{{ end }}"
   destination = "tmp/secrets/vault-nixos3.service-foo"
 }

 auto_auth {
   method {
     type = "approle"
     config = {
       role_id_file_path = "tmp/roleID"
       secret_id_file_path = "tmp/secretID"
     }
   }
 }
