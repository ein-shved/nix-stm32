{ nixpkgs, flake-utils }:
{ mcu
, name
, stm32CubeLibVarName ? "STM32CUBE_PATH"
, buildDir ? "build"
, buildInputs ? [ ]
, installPhase ? null
, postInstall ? "true"
, ...
}@args:
flake-utils.lib.eachDefaultSystem (system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    stdenv = pkgs.stdenv;
    stflash = "${pkgs.stlink}/bin/st-flash";
    stutil = "${pkgs.stlink}/bin/st-util";

    simplescript = body:
      let
        name = "__binscript";
        script = pkgs.writeShellScriptBin name body;
      in
      "${script}/bin/${name}";

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

    mkScript =
      { mkExec
      , name
      , path
      }: pkgs.writeShellScriptBin name ''
        set -e
        if [ -n "$1" ]; then
          exec ${mkExec "$1"}
        else
          exec ${mkExec path}
        fi
      '';

    mkFlasher = args:
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
        fixMakefile = pkgs.runCommandCC "fixMakefile"
          {
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

    firmwareAttrs = {
      inherit name;
      ${stm32CubeLibVarName} = mcu.cubeLib;
    } // builtins.removeAttrs args [
      "buildInputs"
      stm32CubeLibVarName
      "installPhase"
      "mcu"
    ];

  in
  rec {
    packages = rec {
      firmware = stdenv.mkDerivation ({
        buildInputs = [
          pkgs.libusb1
          pkgs.gcc-arm-embedded
        ] ++ buildInputs;
        installPhase =
          if installPhase == null then ''
            mkdir -p "$out/firmware"
            find ${buildDir} -name '*.bin' -or -name '*.elf' | \
              xargs -Ifiles cp files "$out/firmware"
          '' else installPhase;
      } // firmwareAttrs);
      flasher = mkFlasher { path = buildDir; };
      debugger = mkDebug { path = buildDir; };
      inherit format fixMakefile fixGen;

      productFlasher = mkFlasher { path = "${firmware}/firmware"; };
      productDebugger = mkDebug { path = "${firmware}/firmware"; };

      scripts = pkgs.symlinkJoin {
        name = "${name}-scripts";
        paths = [
          flasher
          debugger
          format
          fixMakefile
          fixGen
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
      default = all;
    };
    devShells.default = pkgs.mkShell ({
      buildInputs = [ packages.scripts ];
      inputsFrom = [ packages.firmware ];
    } // firmwareAttrs);
    apps.default = flake-utils.lib.mkApp { drv = packages.flasher; };
  }
)
