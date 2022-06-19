{...}: {
  type = "pure";

  build = {
    lib,
    pkgs,
    stdenv,
    # dream2nix inputs
    externals,
    ...
  }: {
    ### FUNCTIONS
    # AttrSet -> Bool) -> AttrSet -> [x]
    getCyclicDependencies, # name: version: -> [ {name=; version=; } ]
    getDependencies, # name: version: -> [ {name=; version=; } ]
    getSource, # name: version: -> store-path
    # to get information about the original source spec
    getSourceSpec, # name: version: -> {type="git"; url=""; hash="";}
    ### ATTRIBUTES
    subsystemAttrs, # attrset
    defaultPackageName, # string
    defaultPackageVersion, # string
    # all exported (top-level) package names and versions
    # attrset of pname -> version,
    packages,
    # all existing package names and versions
    # attrset of pname -> versions,
    # where versions is a list of version strings
    packageVersions,
    # function which applies overrides to a package
    # It must be applied by the builder to each individual derivation
    # Example:
    #   produceDerivation name (mkDerivation {...})
    produceDerivation,
    ...
  } @ args: let
    l = lib // builtins;

    # the main package
    #defaultPackage = allPackages."${defaultPackageName}"."${defaultPackageVersion}";
    defaultPackage =
    let
      vscode = let
        extensions = l.attrNames subsystemAttrs;
        pins = l.attrValues (l.mapAttrs (n: v:
          {
             name = v.name;
             publisher = v.publisher;
             sha256 = v.hash;
             version = v.version;
          }
          ) packageVersionsClean);
      in
        configuredVscode
        pkgs
        {extensions = extensions;}
        (builtins.concatMap builtins.attrValues (builtins.attrValues subsystemAttrs));

      # check pkgs.vscode-extensions ? extension
      isNixpkgsExtension = pkgs: extension:
        pkgs.lib.attrsets.hasAttrByPath [extension.publisher extension.name]
        pkgs.vscode-extensions;

      nixpkgsExtensions = pkgs: extensions:
        builtins.map (extension:
          pkgs.lib.attrsets.getAttrFromPath [extension.publisher extension.name]
          pkgs.vscode-extensions)
        extensions;

      # generate a list of full attribute paths for each extension string
      configuredVscode = pkgs: vscodeConfig: extensions:
        if vscodeConfig ? extensions
        then
          pkgs.vscode-with-extensions.override {
            vscodeExtensions = let
              partitioned = builtins.partition (x: isNixpkgsExtension pkgs x) extensions;
            in
              (nixpkgsExtensions pkgs partitioned.right)
              ++ (pkgs.vscode-utils.extensionsFromVscodeMarketplace partitioned.wrong);
          }
        else pkgs.vscode;
      in vscode;
      # ###################

    # packages to export
    packages =
      lib.mapAttrs
      (name: version: {
        "${version}" = allPackages.${name}.${version};
      })
      args.packages;

    # manage packages in attrset to prevent duplicated evaluation
    allPackages =
      lib.mapAttrs
      (name: versions:
        lib.genAttrs
        versions
        (version: makeOnePackage name version))
      packageVersions;

    # Generates a derivation for a specific package name + version
    makeOnePackage = name: version: let
      pkg = stdenv.mkDerivation rec {
        pname = l.strings.sanitizeDerivationName name;
        inherit version;
        src = getSource name version;
        buildInputs =
          map
          (dep: allPackages."${dep.name}"."${dep.version}")
          (getDependencies name version);
        # TODO: Implement build phases
        installPhase = ''
          exit 42
        '';
      };
    in
      # apply packageOverrides to current derivation
      if name == "default" then defaultPackage else 
      produceDerivation name pkg;
  in {
    inherit defaultPackage packages;
  };
}
