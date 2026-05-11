# Filtering Telemetry for PII and Sensitive Data

This guide explains how to configure the OpenTelemetry Collector to filter, redact, or drop telemetry data containing personally identifiable information (PII) before it reaches Application Insights.

## Overview

The OpenTelemetry Collector provides several processors that can sanitize telemetry at ingestion time:

| Processor | Use Case | Strength |
|-----------|----------|----------|
| **Attributes** | Delete or hash specific attributes | Simple, performant, attribute-level control |
| **Filter** | Drop entire spans/logs matching conditions | Coarse-grained, pattern-based removal |
| **Transform** | Regex replacement, custom OTTL logic | Fine-grained, pattern matching and redaction |
| **Resource** | Remove resource-level attributes | Targets host/container/process metadata |

## Quick Start: Attributes Processor

Use the **attributes** processor to delete or hash specific fields:

```yaml
processors:
  attributes/redact:
    actions:
      # Delete entirely
      - key: user.email
        action: delete
      - key: http.request.header.authorization
        action: delete
      - key: db.statement
        action: delete
      
      # Hash instead (preserve cardinality for metrics)
      - key: enduser.id
        action: hash
      - key: client.ip
        action: hash

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [attributes/redact, memory_limiter]
      exporters: [azuremonitor]
    logs:
      receivers: [otlp]
      processors: [attributes/redact, memory_limiter]
      exporters: [azuremonitor]
```

## Filter Processor: Pattern-Based Removal

Use the **filter** processor to drop entire spans or log records matching conditions:

```yaml
processors:
  filter/security:
    error_mode: ignore  # Log errors but don't fail on invalid conditions
    traces:
      span:
        # Drop spans containing sensitive patterns
        - 'IsMatch(name, ".*password.*")'
        - 'IsMatch(name, ".*secret.*")'
        - 'IsMatch(attributes["url.full"], ".*password=.*")'
        - 'IsMatch(attributes["db.statement"], ".*SELECT.*password.*")'
        - 'IsMatch(attributes["http.request.body"], ".*credit.*card.*")'
    logs:
      log_record:
        # Drop log records matching PII patterns
        - 'IsMatch(body, ".*email.*@.*")'  # Email
        - 'IsMatch(body, ".*ssn.*\\d{3}-\\d{2}-\\d{4}")'  # Social Security Number
        - 'IsMatch(body, "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b")'  # Credit card
        - 'severity_number < SEVERITY_NUMBER_WARN'  # Drop debug/info logs (optional)

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [filter/security, attributes/redact, memory_limiter]
      exporters: [azuremonitor]
    logs:
      receivers: [otlp]
      processors: [filter/security, attributes/redact, memory_limiter]
      exporters: [azuremonitor]
```

## Transform Processor: Regex Replacement

Use the **transform** processor for pattern-based redaction (replace with placeholder):

```yaml
processors:
  transform/redact:
    log_statements:
      # Replace email addresses with [REDACTED_EMAIL]
      - context: log
        statements:
          - replace_all_patterns(body, "/\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b/g", "[REDACTED_EMAIL]")
          - replace_all_patterns(body, "/\\d{3}-\\d{2}-\\d{4}/g", "[REDACTED_SSN]")
          - replace_all_patterns(body, "/Bearer\\s+[A-Za-z0-9._-]+/g", "[REDACTED_TOKEN]")
    trace_statements:
      # Replace PII in span attributes
      - context: span
        statements:
          - replace_all_patterns(attributes["http.request.header.authorization"], "/Bearer\\s+.+/", "[REDACTED_TOKEN]")
          - replace_all_patterns(attributes["http.url"], "/password=[^&]+/g", "password=[REDACTED]")

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [transform/redact, attributes/redact, memory_limiter]
      exporters: [azuremonitor]
```

## Resource Processor: Remove Host/Process Metadata

Use the **resource** processor to strip resource-level attributes that may contain sensitive information:

```yaml
processors:
  resource/sanitize:
    attributes:
      # Remove user/process/host info
      - key: host.user.name
        action: delete
      - key: process.command_line
        action: delete
      - key: process.executable.name
        action: delete
      - key: container.image.name
        action: delete
      - key: k8s.pod.name
        action: delete

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [resource/sanitize, attributes/redact, memory_limiter]
      exporters: [azuremonitor]
```

## Copilot-Specific Filtering Example

For GitHub Copilot telemetry, consider these filters:

```yaml
processors:
  attributes/copilot:
    actions:
      # Remove chat message content (may contain code snippets, secrets)
      - key: copilot.chat.message.content
        action: delete
      - key: copilot.chat.completion
        action: delete
      
      # Hash user identifiers
      - key: enduser.id
        action: hash
      
      # Remove authorization headers
      - key: http.request.header.authorization
        action: delete
      - key: http.request.header.x-github-token
        action: delete
  
  filter/copilot:
    traces:
      span:
        # Drop spans containing credential/secret patterns
        - 'IsMatch(attributes["http.request.body"], ".*password.*|.*secret.*|.*token.*")'
        - 'IsMatch(attributes["http.url"], ".*api_key=.*|.*token=.*")'
  
  resource/sanitize:
    attributes:
      - key: process.command_line
        action: delete

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [filter/copilot, attributes/copilot, resource/sanitize, memory_limiter]
      exporters: [azuremonitor]
    logs:
      receivers: [otlp]
      processors: [attributes/copilot, resource/sanitize, memory_limiter]
      exporters: [azuremonitor]
```

## OTTL Function Reference

Common OTTL (OpenTelemetry Transformation Language) functions for filtering:

| Function | Example | Description |
|----------|---------|-------------|
| `IsMatch(value, pattern)` | `IsMatch(body, ".*password.*")` | Regex pattern matching |
| `Contains(value, substring)` | `Contains(attributes["url"], "secret")` | Substring matching |
| `StartsWith(value, prefix)` | `StartsWith(name, "internal.")` | Prefix matching |
| `replace_all_patterns()` | `replace_all_patterns(body, "/email/g", "[REDACTED]")` | Pattern replacement |
| `resource.attributes["key"]` | `resource.attributes["host.name"] == "localhost"` | Resource attribute access |

## Best Practices

1. **Layer your filters**: Combine multiple processors for defense-in-depth
   - `filter` → drop entire spans/logs
   - `transform` → redact specific patterns
   - `attributes` → delete/hash remaining sensitive fields

2. **Test with debug exporter**: Use the debug exporter to verify filtering before sending to production:
   ```yaml
   exporters:
     debug:
       verbosity: detailed
   service:
     pipelines:
       traces:
         receivers: [otlp]
         processors: [filter/security, attributes/redact]
         exporters: [debug, azuremonitor]
   ```

3. **Use `error_mode: ignore`**: Prevent invalid filter conditions from breaking the pipeline
   ```yaml
   filter/security:
     error_mode: ignore  # Silently skip invalid conditions
   ```

4. **Hash instead of delete**: When you need to preserve cardinality for analytics
   ```yaml
   actions:
     - key: user.id
       action: hash  # Keeps distinct user count metrics intact
   ```

5. **Monitor filter impact**: Track how many telemetry items are dropped
   ```yaml
   processors:
     memory_limiter:
       check_interval: 5s
       limit_mib: 4000
   ```

## Validating Your Configuration

Use the `validate` command to check syntax before deploying:

```bash
otelcol validate --config=config.yaml
```

Print the final merged configuration:

```bash
otelcol print-config --config=config.yaml --mode=redacted
```

## Security Considerations

- **Always test regex patterns** before production; overly aggressive filters can lose critical telemetry
- **Log what you filter**: Enable collector internal telemetry to audit dropped data
- **Rotate filter rules**: Update patterns as new secret formats emerge
- **Defense-in-depth**: Combine filtering with TLS, authentication, and network policies on the collector itself

## Troubleshooting

**Filter not working?**
- Check `error_mode` is set to `ignore` (not `propagate`)
- Verify regex escaping (double-backslash in YAML: `\\d`)
- Use `otelcol validate` to catch syntax errors

**Too much data being filtered?**
- Use debug exporter to inspect unfiltered data first
- Test filter conditions in isolation
- Consider using `hash` action instead of `delete` to preserve metrics

**Performance issues?**
- Complex regex patterns in high-volume pipelines can cause CPU spikes
- Use `filter` processor (faster) before `transform` processor (slower)
- Consider sampling with `probabilistic_sampler` as well

## References

- [OpenTelemetry Collector Configuration](https://opentelemetry.io/docs/collector/configuration/)
- [Attributes Processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/attributesprocessor)
- [Filter Processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/filterprocessor)
- [Transform Processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/transformprocessor)
- [OTTL Syntax](https://github.com/open-telemetry/opentelemetry-collector/tree/main/pkg/ottl)
