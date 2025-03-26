{pkgs, ...}: {
  # environment.systemPackages = with pkgs; [
  #   sshfs
  # ];
  programs.direnv.enable = true;
  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };
}
