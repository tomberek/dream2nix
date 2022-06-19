{
  dlib,
  lib,
  ...
}: let
  l = lib // builtins;
in {
  type = "impure";

  discoverProject = tree:
    l.any
    (filename: l.hasSuffix "extensions.txt" filename)
    (l.attrNames tree.files);

  # A derivation which outputs a single executable at `$out`.
  # The executable will be called by dream2nix for translation
  # The input format is specified in /specifications/translator-call-example.json.
  # The first arg `$1` will be a json file containing the input parameters
  # like defined in /src/specifications/translator-call-example.json and the
  # additional arguments required according to extraArgs
  #
  # The program is expected to create a file at the location specified
  # by the input parameter `outFile`.
  # The output file must contain the dream lock data encoded as json.
  # See /src/specifications/dream-lock-example.json
  translateBin = {
    # dream2nix utils
    utils,
    # nixpkgs dependenies
    bash,
    jq,
    writeScriptBin,
    coreutils,
    nix,
    curl,
    unzip,
    ...
  }:
    utils.writePureShellScript
    [
      bash
      coreutils
      jq
      nix
      curl
      unzip
    ]
    ''
      # accroding to the spec, the translator reads the input from a json file
      jsonInput=$1

      # read the json input
      outputFile=$WORKDIR/$(${jq}/bin/jq '.outputFile' -c -r $jsonInput)
      source=$(${jq}/bin/jq '.source' -c -r $jsonInput)
      relPath=$(jq '.project.relPath' -c -r $jsonInput)

      function get_vsixpkg() {
          while read -r publisher name; do
            N="$publisher.$name"
            URL="https://$publisher.gallery.vsassets.io/_apis/public/gallery/publisher/$publisher/extension/$name/latest/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
            echo fetching "$publisher.$name" >&2
            curl --silent --show-error --retry 3 --fail -X GET -o "$N.zip" "$URL"
            VER=$(jq -r '.version' <(unzip -qc "$N.zip" "extension/package.json"))
            SHA=$(nix-hash --flat --base32 --type sha256 "$N.zip")

            cat << EOF
            {
            "$N" : {
              "$VER": {
                "publisher": "$publisher",
                "name":  "$name",
                "sha256": "$SHA",
                "version": "$VER"
                }
              }
            }
      EOF
          done
      }

      mkdir -p $(dirname "$outputFile")
      cat << EOF > $outputFile
      {
        "_generic": {
          "subsystem": "vscode",
          "defaultPackage": "default",
          "translatorArgs": "",
          "packages": {
            "default": "1"
          },
          "sourcesAggregatedHash": null,
          "location": ""
        },
        "_subsystem": $(cat $source/extensions.txt | get_vsixpkg | jq -s 'reduce .[] as $x ({}; . * $x)'),
        "sources": {
          "default": {"1":{}}
        }
      }
      EOF
    '';

  extraArgs = {};
}
