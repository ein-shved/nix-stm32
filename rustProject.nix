{ nixpkgs, flake-utils, rust-overlay }:
{ mcu, ... }@args:
flake-utils.lib.eachDefaultSystem (system:
  let
    target = if mcu ? rustTarget then mcu.rustTarget else
    abort ''
      The rust target does not provided for requested mcu
    '';
    overlays = [ (import rust-overlay) ];
    pkgs = import nixpkgs {
      inherit system overlays;
    };
    rustVersion = pkgs.rust-bin.stable.latest.default.override {
      targets = [ target ];
    };

    package = pkgs.rustPlatform.buildRustPackage
      ({
        doCheck = false;
        nativeBuildInputs = [ rustVersion ];
        buildPhase = ''
          runHook preBuild
          ${rustVersion}/bin/cargo build -j $NIX_BUILD_CORES --frozen
          runHook postBuild
        '';
        dontCargoInstall = true;
        installPhase = ''
          mkdir -p $out/bin
          ${rustVersion}/bin/cargo install -j $NIX_BUILD_CORES --root $out --path .
        '';
      } // builtins.removeAttrs args [ "mcu" ]);
    runner = pkgs.writeShellScriptBin package.name ''
      ${pkgs.probe-run}/bin/probe-run --chip ${mcu.chip} \
        $(find ${package} -type f -executable)
    '';
  in
  {
    devShells.default = pkgs.mkShellNoCC {
      buildInputs = [ rustVersion pkgs.probe-run ];
    };
    packages.default = package;
  } // (
    if mcu ? chip then {
      apps.default = flake-utils.lib.mkApp { drv = runner; };
    } else { }
  ))
