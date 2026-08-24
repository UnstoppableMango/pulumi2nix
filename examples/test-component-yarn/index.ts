import * as pulumi from "@pulumi/pulumi";

export interface SalutationArgs {
    name: pulumi.Input<string>;
}

export class Salutation extends pulumi.ComponentResource {
    public readonly message: pulumi.Output<string>;

    constructor(name: string, args: SalutationArgs, opts?: pulumi.ComponentResourceOptions) {
        super("test-component-yarn:index:Salutation", name, args, opts);
        this.message = pulumi.interpolate`Greetings, ${args.name}!`;
        this.registerOutputs({ message: this.message });
    }
}
