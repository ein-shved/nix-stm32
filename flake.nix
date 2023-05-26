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

    cube2rustSrc.url = github:dimpolo/cube2rust;
    cube2rustSrc.flake = false;
  };
  outputs = { self, nixpkgs, cube2rustSrc, ... }@inputs :
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
  rec {
    mcus = rec {
      stm32f1 = mkMcuRegex 1 "1.8.4";
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
      cube2rust = pkgs.callPackage ./cube2rust { src = cube2rustSrc; };

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
            find "${path}" -type f -name '*.h' -print \
                -or -name '*.c' -print \
                -or -name '*.cpp' -print \
                -or -name '*.hpp' -print \
              | xargs ${pkgs.clang-tools}/bin/clang-format \
                -style=file:"$format_file" -i
          '';
        });

      fixMakefile =
        let
          fixMakefile = pkgs.runCommandCC "fixMakefile" {
              src = ./FixMakefile.cpp;
            } ''
              g++ -o fixMakefile $src -std=c++17
              install -D fixMakefile $out/bin/fixMakefile
            '';
        in
          pkgs.writeShellScriptBin "fixMakefile" ''
            dstfile=$1
            shift
            re="''${1-${if mcu.libRegex == null then "" else mcu.libRegex}}"
            shift
            fmt="''${1-\$(${stm32CubeLibVarName})}"
            if [ -z "$re" ] || [ -z "$fmt" ]; then
              ${if mcu.libRegex == null then ''
                echo "Usage: $0 MAKEFILE REGEX [ FMT ]" >&2
              '' else ''
                echo "Usage: $0 [ MAKEFILE REGEX FMT ]" >&2
              ''
               }
               exit 1;
            fi
            if [ -f "$dstfile"]; then
              if git rev-parse --is-inside-work-tree 2>/dev/null >/dev/null;
              then
                dstfile="$(git rev-parse --show-toplevel)/Makefile"
              fi
            fi
            if [ ! -f "$dstfile" ]; then
              ${if mcu.libRegex == null then ''
                echo "Usage: $0 MAKEFILE REGEX [ FMT ]" >&2
              '' else ''
                echo "Usage: $0 MAKEFILE [ REGEX FMT ]" >&2
              ''
               }
            fi
            ${fixMakefile}/bin/fixMakefile "$re" "$fmt" "$dstfile"

            # There could be left the date of Makefie; generation as the last
            # change. We can drop it

            numstat="$(git diff --numstat  -- "$dstfile")"
            addings="$(echo $numstat | awk '{ print $1 }')"
            removals="$(echo $numstat | awk '{ print $2 }')"
            nummatches="$(git diff  -- $dstfile |\
              grep '[+-]# File automatically-generated by tool' -o |\
              wc -l)"
            if [ "$addings" == "1" ] && [ "$removals" == "1" ] && \
                [ "$nummatches" == "2" ]; then
              git checkout --force "$dstfile" >/dev/null 2>/dev/null
            fi
          '';

      fixGen = pkgs.writeShellScriptBin "fixGen" ''
        ${fixMakefile}/bin/fixMakefile && ${format}/bin/format
      '';

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
      inherit format fixMakefile fixGen cube2rust;

      productFlasher = mkFlasher { path = "${firmware}/firmware";  };
      productDebugger = mkDebug { path = "${firmware}/firmware";  };

      scripts = pkgs.symlinkJoin {
        name = "${name}-scripts";
        paths = [
          flasher
          debugger
          format
          fixMakefile
          fixGen
          cube2rust
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
