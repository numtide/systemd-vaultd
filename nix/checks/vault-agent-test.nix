{
  name = "vault-agent";
  nodes.server = {
    config,
    pkgs,
    ...
  }: {
    imports = [
      ./dev-vault-server.nix
      ../modules/vault-agent.nix
    ];

    services.vault.agents.test.settings = {
      vault = {
        address = "http://localhost:8200";
      };
      template = {
        contents = ''{{ with secret "secret/my-secret" }}{{ .Data.data.foo }}{{ end }}'';
        destination = "/run/render.txt";
      };

      auto_auth = {
        method = [
          {
            type = "approle";
            config = {
              role_id_file_path = "/tmp/roleID";
              secret_id_file_path = "/tmp/secretID";
              remove_secret_id_file_after_reading = false;
            };
          }
        ];
      };
    };
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("vault.service")
    machine.wait_for_open_port(8200)
    machine.wait_for_unit("setup-vault-agent-approle.service")

    # It should be able to write our template
    out = machine.wait_until_succeeds("cat /run/render.txt")
    print(out)
    assert out == "bar"
  '';
}
