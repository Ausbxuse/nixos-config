{...}: {
  environment.etc."ollama/base".text = "1\n";
  environment.etc."nixos/base".text = "1\n";

  specialisation.docked.configuration = {
    environment.etc."nixos/docked".text = "1\n";
  };
}
