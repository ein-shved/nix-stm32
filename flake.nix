{
  description = "The stm32 development utilities";
  inputs = {
    nixpkgs.url = "nixpkgs";

    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";

    stm32CubeF1.url = github:STMicroelectronics/STM32CubeF1/v1.8.4;
    stm32CubeF1.flake = false;

    stm32CubeF2.url = github:STMicroelectronics/STM32CubeF2/v1.9.3;
    stm32CubeF2.flake = false;

    stm32CubeF3.url = github:STMicroelectronics/STM32CubeF3/v1.11.3;
    stm32CubeF3.flake = false;

    stm32CubeF4.url = github:STMicroelectronics/STM32CubeF4/v1.27.1;
    stm32CubeF4.flake = false;
  };
  outputs = { self, nixpkgs, flake-utils, rust-overlay, ... }@inputs:
    let
      _pkgs = nixpkgs.legacyPackages.x86_64-linux;
      mkMcu = input: { cubeLib = input; };
      mkLibRegex = series: version:
        "/\\S*/STM32Cube_FW_F${builtins.toString series}_V${version}";
      mkMcuRegex = series: version: {
        cubeLib = inputs."stm32CubeF${builtins.toString series}";
        libRegex = mkLibRegex series version;
      };
    in
    {
      mcus = rec {
        stm32f1 = mkMcuRegex 1 "1.8.4" // {
          rustTarget = "thumbv7m-none-eabi";
        };
        stm32f103 = stm32f1 // {
          firmwareStart = "0x8000000";
          chip = "STM32F103C8";
        };

        stm32f2 = mkMcu inputs.stm32CubeF2;
        stm32f3 = mkMcu inputs.stm32CubeF3;
        stm32f4 = mkMcu inputs.stm32CubeF4;
      };
      mkFirmware = import ./cProject.nix {
        inherit nixpkgs flake-utils;
      };
      mkRustFirmware = import ./rustProject.nix {
        inherit nixpkgs flake-utils rust-overlay;
      };
    };
}
