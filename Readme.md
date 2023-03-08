# STM 32 Nix Builder

This is generalized helper for projects based on STM32 microcontrollers and
nix-based builders. It assumes, you use st-link programmer and Stm32Cube HAL
lib.

## Flake

Use mkFirmware function in your flake.nix file like next:

```nix
{
  inputs = {
    stm32.url = github:ein-shved/nix-stm32;
  };
  outputs = { self, stm32, ... } :
  stm32.mkFirmware {
    name = "my-stm32-project";
    src = ./.;
    mcu = stm32.mcus.stm32f103;
  };
}
```

### MCU

The `nix-stm32` flake outputs the set of MCU Lines descriptors in `mcus`
outputs. Each descriptor may has next fields:

* `cubeLib` - the path to `STM32Cube` HAL library;

* `firmwareStart` - the address of firmware start (the stringified constant).

There next descriptors described withing `mcus` output:

* `stm32f{1..4}` - the several supported of stm32fxxx lines. Each of them uses
  STMicroelectronics/STM32CubeFX as `cubeLib` field and do not define the
  `firmwareStart` field;

* `stm32f103` - the concrete stm32f103 mcu (mostly for bluepill board) with
  `firmwareStart` equals to `0x8000000`.

### mkFirmware

The function `mkFirmwre` produces the set of derivations:

* `firmware` - the target derivation with `firmware` folder to which placed all
  `*.elf` and `*.bin` files produced inside `buildDir`;

* `flasher` - the script which runs `st-flash` to flash `*.bin` firmware file
  found withing `buildDir` directory. You can call the script with another path
  where to search for firmware file;

* `productFlasher` - the same as `flasher` but used produced by `firmware`
  derivation `*.bin` file by default;

* `debugger` - the scripts which runs `st-util` with gdb server in background
  and attaches the gdb shell to it with `*.elf` found withing `buildDir`
  directory. You can call the script with another path where to search for
  firmware file;

* `productDebugger` - the same as `debugger` but used produced by `firmware`
  derivation `*.elf` file by default;

* `scripts` - a join of `flasher` and `debugger` derivations;

* `productScripts` - a join of `productFlasher` and `productDebugger`
  derivations;

* `all` - a join of `productFlasher`, `productDebugger` and `firmware`
  derivations.

The function `mkFirmware` accepts the set of arguments same to `mkDerivation`
function and additionally next:

* `mcu` - the describer for [MCU](#MCU)

* `pkgs` - the legacy nixpkgs set (defined by default)

* `stm32CubeLibVarName` - the name of environment variable of HAL library to
  define for builder (`STM32CUBE_PATH` by default)

* `buildDir` - the relative path to build directory (`build` by default)

## Usage

Say, you used nix-stm32 shown [above](#Flake). Then you may use work with your
flake in several ways:

### Final product

```bash
$ nix build .#all       #To build firmware and create the all-derivation
$ ./result/bin/flasher  #To upload the firmware to board
```

### Developing

```bash
$ nix build .#scripts       #To prepare scripts in current folder
$ nix develop .#firmware    #To run development shell
$ make -j8                  #To build the intermidiate firmware
$ ./result/bin/flasher      #To flash the firmware from current build
                            #dirictory
$ ./result/bin/debugger     #To connect to board with gdb
```
