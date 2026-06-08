# Adding Extra Metadata

The script [wsl-setup-otel.sh](wsl-setup-otel.sh) sets up OpenTelemetry environment variables before VS Code starts so Copilot telemetry can include metadata that is not present in the raw chat messages.

Copilot telemetry is useful, but it has limits. On its own, it can tell us that an agent was used, which model handled the request, and when telemetry was emitted. What it usually cannot tell us is the business context around the person using it, such as which squad they belong to or which product they are working on.

That missing context matters because raw usage data is hard to interpret in isolation. If we only track agent usage and underlying model usage, we can see volume, but not who the usage belongs to in an organizational sense. Adding squad and product metadata makes the telemetry useful for grouping activity, understanding adoption by team, and answering questions like which areas of the org are using Copilot most heavily.

The script helps with that by creating OpenTelemetry environment variables before VS Code starts. It captures the collector endpoint and telemetry protocol, then adds extra resource attributes for the user’s squad and product. Those environment variables are picked up by VS Code telemetry and injected into the exported data.

The key detail is timing: the variables must already exist in the environment before VS Code launches, because VS Code telemetry reads them at startup and uses them to inject the metadata into exported telemetry.

## Script Flow and User Prompts

Use the script by sourcing it so exported variables are applied to the current shell before launching VS Code:

```bash
source ./wsl-setup-otel.sh
```

Flow of the script:

1. Shows startup banner: `OpenTelemetry environment setup for WSL`
2. Prompts for collector endpoint (defaults to current environment value or script default)
3. Prompts for squad name (defaults to current environment value if present)
4. Prompts for product name (defaults to current environment value if present)
5. Builds `OTEL_RESOURCE_ATTRIBUTES` from squad/product
6. Prints all proposed environment variable values
7. Asks for final confirmation
8. If confirmed and sourced, exports values into the current shell
9. If not sourced (run directly), prints export commands and reminds you to use `source`

Prompts the user must answer:

- `Collector endpoint [<default>]`:
	- Press Enter to accept default, or type a new endpoint URL
- `Squad name [<default>]`:
	- Press Enter to keep default/blank, or type your squad
- `Product name [<default>]`:
	- Press Enter to keep default/blank, or type your product
- `Apply these values to the current shell? [Y/n]`:
	- Enter `Y`/Enter to apply, or `n` to abort

Example prompt sequence:

```text
OpenTelemetry environment setup for WSL
Collector endpoint [https://collectorv2.purpleocean-eb978143.uksouth.azurecontainerapps.io]:
Squad name []: Platform Engineering
Product name []: Copilot Dashboard

Proposed values:
	OTEL_EXPORTER_OTLP_ENDPOINT=https://collectorv2.purpleocean-eb978143.uksouth.azurecontainerapps.io
	OTEL_EXPORTER_OTLP_PROTOCOL=otlp-http
	OTEL_RESOURCE_ATTRIBUTES=org.squad=Platform Engineering,org.product=Copilot Dashboard

Apply these values to the current shell? [Y/n]: Y
```
