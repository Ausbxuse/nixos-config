{...}: {
  environment.etc."ollama/base".text = "1\n";

  specialisation.docked.configuration = {
    environment.etc."ollama/docked".text = "1\n";
  };
}
