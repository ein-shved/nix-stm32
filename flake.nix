{
  description = "The stm32 development utilities";
  inputs = {
    nixpkgs.url = "nixpkgs";

    stm32CubeF1.url = github:STMicroelectronics/STM32CubeF1/v1.8.4;
    stm32CubeF1.flake = false;

    stm32CubeF2.url = github:STMicroelectronics/STM32CubeF2/v1.9.3;
    stm32CubeF2.flake = false;

    stm32CubeF3.url = github:STMicroelectronics/STM32CubeF3/v1.11.3;
    stm32CubeF3.flake = false;

    stm32CubeF4.url = github:STMicroelectronics/STM32CubeF4/v1.27.1;
    stm32CubeF4.flake = false;
  };
  outputs = { self, nixpkgs, ... }@inputs :
  let
    _pkgs = nixpkgs.legacyPackages.x86_64-linux;
    mkMcu = input: { cubeLib = input; };
  in
  rec {
    mcus = rec {
      stm32f1 = mkMcu inputs.stm32CubeF1;
      stm32f103 = stm32f1 // {
        firmwareStart = "0x8000000";
      };

      stm32f2 = mkMcu inputs.stm32CubeF2;
      stm32f3 = mkMcu inputs.stm32CubeF3;
      stm32f4 = mkMcu inputs.stm32CubeF4;
    };
    mkFirmware = {
      mcu,
      pkgs ? _pkgs,
      stm32CubeLibVarName ? "STM32CUBE_PATH",
      buildDir ? "build",
      buildInputs ? [],
      installPhase ? null,
      postInstall ? "true",
      ...
    }@args :
    let
      name = args.name;
      stdenv = pkgs.stdenv;
      stflash = "${pkgs.stlink}/bin/st-flash";
      stutil = "${pkgs.stlink}/bin/st-util";

      simplescript = body: let
        name = "__binscript";
        script = pkgs.writeShellScriptBin name body;
      in "${script}/bin/${name}";

      getoneof = simplescript ''
        files="$(eval echo "$*")"
        nfiles="$(echo "$files" | wc -w)"
        if [ x"$nfiles" == x"1" ] && [ -f "$files" ]; then
          echo "$files"
          exit 0
        else
          echo "Found several files for operation: $*" >&2
        fi
        exit 1
      '';

      mkScript = {
        mkExec,
        name,
        path,
      }: pkgs.writeShellScriptBin name ''
        set -e
        if [ -n "$1" ]; then
          exec ${mkExec "$1"}
        else
          exec ${mkExec path}
        fi
      '';

      mkFlasher = args :
        mkScript ({
          name = "flasher";
          mkExec = path: ''
            ${stflash} --reset write "$(${getoneof} "${path}/*.bin")" \
              ${mcu.firmwareStart}
          '';
        } // args);

      mkDebug = args:
        let
          runner = simplescript ''
            set -e
            port="$(( $RANDOM % 10000 + 42424 ))"
            stpid=
            elf="$1"
            function cleanup {
              if [ -n "$stpid" ]; then
                echo "Stopping stutil on $stpid"
                kill $stpid
                wait $stpid
              fi
            }
            trap cleanup EXIT
            ${stutil} -p $port >/dev/null 2>/dev/null &
            stpid="$!"
            ${pkgs.gdb}/bin/gdb "$elf" -ex \
              'target extended-remote localhost:'"$port"
          '';
        in
        mkScript ({
          name = "debug";
          mkExec = path: ''
            ${runner} "$(${getoneof} "${path}/*.elf")"
          '';
        } // args);

      format = mkScript ({
          name = "format";
          path = ".";
          mkExec = path: simplescript ''
            format_file="${path}/.clang-format"
            if [ ! -f "$format_file" ]; then
              format_file="${path}/_clang-format"
            fi
            if [ ! -f "$format_file" ]; then
              format_file="${builtins.toString ./clang-format.yaml}"
            fi
            find "${path}" -type f -name "*.[h|c|cpp|hpp]" -print  | \
              xargs ${pkgs.clang-tools}/bin/clang-format \
                -style=file:"$format_file" -i
          '';
        });

    in
    rec {
      firmware = stdenv.mkDerivation ({
        buildInputs = with pkgs; [
          pkgs.libusb1
          gcc-arm-embedded
        ] ++ buildInputs;
        ${stm32CubeLibVarName} = mcu.cubeLib;
        installPhase = if installPhase == null then ''
          mkdir -p "$out/firmware"
          find ${buildDir} -name '*.bin' -or -name '*.elf' | \
            xargs -Ifiles cp files "$out/firmware"
        '' else installPhase;
      } // builtins.removeAttrs args [
        "buildInputs"
        stm32CubeLibVarName
        "installPhase"
        "mcu"
      ]);

      flasher = mkFlasher { path = buildDir; };
      debugger = mkDebug { path = buildDir; };
      inherit format;

      productFlasher = mkFlasher { path = "${firmware}/firmware";  };
      productDebugger = mkDebug { path = "${firmware}/firmware";  };

      scripts = pkgs.symlinkJoin {
        name = "${name}-scripts";
        paths = [
          flasher
          debugger
          format
        ];
      };

      productScripts = pkgs.symlinkJoin {
        name = "${name}-productScripts";
        paths = [
          productFlasher
          productDebugger
        ];
      };

      all = pkgs.symlinkJoin {
        name = "${name}-all";
        paths = [
          firmware
          productScripts
        ];
      };
    };
  };
}
