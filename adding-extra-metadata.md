# Adding Extra Metadata

The script [wsl-setup-otel.sh](wsl-setup-otel.sh) sets up OpenTelemetry environment variables before VS Code starts so Copilot telemetry can include metadata that is not present in the raw chat messages.

Copilot telemetry is useful, but it has limits. On its own, it can tell us that an agent was used, which model handled the request, and when telemetry was emitted. What it usually cannot tell us is the business context around the person using it, such as which squad they belong to or which product they are working on.

That missing context matters because raw usage data is hard to interpret in isolation. If we only track agent usage and underlying model usage, we can see volume, but not who the usage belongs to in an organizational sense. Adding squad and product metadata makes the telemetry useful for grouping activity, understanding adoption by team, and answering questions like which areas of the org are using Copilot most heavily.

The script helps with that by creating OpenTelemetry environment variables before VS Code starts. It captures the collector endpoint and telemetry protocol, then adds extra resource attributes for the user’s squad and product. Those environment variables are picked up by VS Code telemetry and injected into the exported data.

The key detail is timing: the variables must already exist in the environment before VS Code launches, because VS Code telemetry reads them at startup and uses them to inject the metadata into exported telemetry.
