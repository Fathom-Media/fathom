{
  description = "A modern desktop client for Jellyfin, with an optional built-in YouTube player and Seerr requests";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = inputs:
    let
      # Fathom's desktop target on Nix is Linux only, so evaluate for the Linux
      # systems rather than every platform nixpkgs exposes.
      linuxPkgs = inputs.nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ] (system: inputs.nixpkgs.legacyPackages.${system});
    in
    {
      packages = builtins.mapAttrs (system: pkgs: rec {
        default = fathom;

        fathom = pkgs.flutter344.buildFlutterApplication (finalAttrs: {
          pname = "fathom";
          version = "0.12.0";

          src = ./.;

          buildInputs = with pkgs; [ mpv ];

          autoPubspecLock = ./pubspec.lock;

          postInstall = ''
            install -Dm644 ${finalAttrs.src}/linux/packaging/icons/fathom-512.png $out/share/icons/hicolor/512x512/apps/app.fathom.player.png
            install -Dm644 ${finalAttrs.src}/linux/packaging/icons/fathom-256.png $out/share/icons/hicolor/256x256/apps/app.fathom.player.png
            install -Dm644 ${finalAttrs.src}/linux/packaging/icons/fathom-128.png $out/share/icons/hicolor/128x128/apps/app.fathom.player.png
            install -Dm644 ${finalAttrs.src}/linux/packaging/app.fathom.player.desktop $out/share/applications/fathom.desktop
          '';
        });
      }) linuxPkgs;

      apps =
        let
          mkApp = system: {
            fathom = {
              type = "app";
              program = "${inputs.self.packages.${system}.fathom}/bin/fathom";
            };
          };
        in
        builtins.mapAttrs (system: pkgs: mkApp system) linuxPkgs;

      overlays.default = final: prev: {
        fathom = inputs.self.packages.${final.system}.fathom;
      };

      devShells = builtins.mapAttrs (system: pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            flutter344
            dart
          ];
        };
      }) linuxPkgs;
    };
}
