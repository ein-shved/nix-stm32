{ src, lib, makeWrapper, cargo, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "cube2rust";
  version = "0.1";
  inherit src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };

  nativeBuildInputs = [ makeWrapper ];
  postFixup = ''
    wrapProgram $out/bin/cube2rust --prefix PATH : ${lib.makeBinPath [ cargo ]}
  '';

  meta = with lib; {
    description = "A tool for generating a rust project from a STM32CubeMX ioc file";
    homepage = "https://github.com/dimpolo/cube2rust/tree/master";
    license = licenses.mit;
  };
}
