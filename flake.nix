{
	description = "Language-neutral complexity and memory gates with external immutable history";
	inputs.nixpkgs.url = "github:NixOS/nixpkgs/9fbb54b33e91ee4ca368e35a78e0613c720600b3";
	inputs.printable-binary = {
		url = "github:pmarreck/printable_binary/3f697d53f447144e9ba1b73c4217b382f32b4d62";
		flake = false;
	};
	inputs.dotfiles = { url = "github:pmarreck/dotfiles"; flake = false; };
	outputs = { self, nixpkgs, printable-binary, dotfiles }:
		let
			moduleContract = import ./tests/nix/history-storage.nix { lib = nixpkgs.lib; };
			systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
			all = nixpkgs.lib.genAttrs systems;
			pkgsFor = system: nixpkgs.legacyPackages.${system};
			luaFor = pkgs: pkgs.luajit.withPackages (p: [ p.lua-cjson p.luv ]);
			tools = pkgs: [ (luaFor pkgs) pkgs.bash pkgs.coreutils pkgs.gitMinimal ];
			package = system:
				let pkgs = pkgsFor system;
				in pkgs.stdenvNoCC.mkDerivation {
					pname = "performance-profile";
					version = "0.1.0";
					src = nixpkgs.lib.fileset.toSource {
						root = ./.;
						fileset = nixpkgs.lib.fileset.unions [ ./src ./bin ./tests ./test ./cg ./mg ./bm ./profiling.json ./LICENSE ];
					};
					nativeBuildInputs = tools pkgs ++ [ pkgs.makeWrapper ];
					strictDeps = true;
					dontBuild = true;
					doCheck = true;
					PERFORMANCE_PRINTABLE_BINARY = "${printable-binary}";
					CAPTURE_LIB = "${dotfiles}/bin/src/capture.bash";
					PERFORMANCE_MODULE_CONTRACT = if moduleContract then "passed" else "failed";
					checkPhase = ''
						runHook preCheck
						patchShebangs bin tests/cli test cg mg bm
						export HOME="$TMPDIR/home"
						mkdir -p "$HOME"
						git config --global user.name "profile tests"
						git config --global user.email "tests@example.invalid"
						git init -b yolo -q
						git add .
						git commit -qm fixture
						./test
						runHook postCheck
					'';
					installPhase = ''
						mkdir -p "$out/bin" "$out/share/performance-profile"
						cp -r src bin "$out/share/performance-profile/"
						cp LICENSE "$out/share/performance-profile/"
						makeWrapper "${luaFor pkgs}/bin/luajit" "$out/bin/performance-profile" \
							--add-flags "$out/share/performance-profile/bin/performance-profile" \
							--set PERFORMANCE_PRINTABLE_BINARY "${printable-binary}" \
							--prefix PATH ':' "${nixpkgs.lib.makeBinPath (tools pkgs)}"
					'';
					meta = {
						description = "External-history performance, complexity and memory controls";
						license = nixpkgs.lib.licenses.mit;
						mainProgram = "performance-profile";
						platforms = systems;
					};
				};
		in assert moduleContract; {
			inherit moduleContract;
			nixosModules.history-storage = import ./nix/history-storage.nix;
			packages = all (system: { default = package system; });
			apps = all (system: { default = { type = "app"; program = "${package system}/bin/performance-profile"; }; });
			checks = all (system: { package = package system; });
			devShells = all (system:
				let pkgs = pkgsFor system;
				in { default = pkgs.mkShell {
					packages = tools pkgs ++ [ pkgs.hyperfine ];
					PERFORMANCE_PRINTABLE_BINARY = "${printable-binary}";
					CAPTURE_LIB = "${dotfiles}/bin/src/capture.bash";
					PERFORMANCE_MODULE_CONTRACT = if moduleContract then "passed" else "failed";
				}; });
		};
}
