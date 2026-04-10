{...}: {
  environment.etc."llamacpp/base".text = "1\n";

  specialisation.docked.configuration = {
    environment.etc."llamacpp/docked".text = "1\n";
  };
}
