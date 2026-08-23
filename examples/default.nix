# Every example is a perSystem module declaring one `pulumi.*` entry. This is
# also the module's own dogfooding: if a builder can't be expressed through the
# options, it shows up here first.
{ ... }:
{
  imports = [
    ./pulumi-command
    ./pulumi-command-schema
    ./pulumi-random
    ./pulumi-random-schema
    ./pulumi-terraform-provider
    ./test-component
    ./test-component-schema
  ];
}
