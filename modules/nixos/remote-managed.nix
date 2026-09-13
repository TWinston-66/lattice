_: {
  ### DEPLOY ACCESS ###
  users.users."winston".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5CS1KFrnBau01Uq15NrORDcXbSzHtDKkwBuQy5qNPU"
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
