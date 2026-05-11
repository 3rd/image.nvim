{
  description = "image.nvim development shell";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems =
        fn:
        nixpkgs.lib.genAttrs systems (
          system:
          fn (
            import nixpkgs {
              inherit system;
            }
          )
        );
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          luaPackages = pkgs.lua51Packages;
          runtimeLibraries = with pkgs; [
            imagemagick
            ncurses
            readline
            zlib
          ];
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              act
              git
              gnumake
              imagemagick
              lua-language-server
              neovim
              pkg-config
              stdenv.cc
              stylua
              ncurses
              readline
              zlib
              luaPackages.busted
              luaPackages.dkjson
              luaPackages.lua-term
              luaPackages.luarocks
              luaPackages.luassert
              luaPackages.luasystem
              luajitPackages.magick
              luaPackages.mediator_lua
              luaPackages.nlua
              luaPackages.penlight
              luaPackages.say
            ];

            shellHook = nixpkgs.lib.optionalString pkgs.stdenv.isLinux ''
              export LD_LIBRARY_PATH="${nixpkgs.lib.makeLibraryPath runtimeLibraries}:''${LD_LIBRARY_PATH:-}"
            '';
          };
        }
      );
      packages = forAllSystems (pkgs: {
        act = pkgs.act;
      });
      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
