{
  description = "asm.io dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems = {
      url = "github:nix-systems/default";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          system = "${system}";
          config.allowUnfree = true;
        };
        terraform = pkgs.terraform.withPlugins(p: with p; [
          archive
          aws
        ]);
      in
      {
        devShell = pkgs.mkShell {
          packages = [
            pkgs.awscli
            pkgs.direnv
            pkgs.git
            pkgs.httpie
            pkgs.just
            pkgs.jq
            pkgs.nodejs_20
            pkgs.python3
            pkgs.s3cmd

            terraform
          ];
        };
      });
}
