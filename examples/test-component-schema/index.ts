import * as pulumi from "@pulumi/pulumi";

export interface GreetingArgs {
    name: pulumi.Input<string>;
}

export class Greeting extends pulumi.ComponentResource {
    public readonly message: pulumi.Output<string>;

    constructor(name: string, args: GreetingArgs, opts?: pulumi.ComponentResourceOptions) {
        super("test-component-schema:index:Greeting", name, args, opts);
        this.message = pulumi.interpolate`Hello, ${args.name}!`;
        this.registerOutputs({ message: this.message });
    }
}
