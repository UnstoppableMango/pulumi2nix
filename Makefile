.PHONY: build update check lint integration format fmt

build:
	nix build .#

update:
	nix flake update

check lint:
	nix flake check

integration:
	nix flake check ./integration --override-input pulumi2nix . --keep-going

format fmt:
	nix fmt
