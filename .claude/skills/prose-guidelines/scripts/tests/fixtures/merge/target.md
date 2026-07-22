# Merge fixture target

This section describes the pipeline. The flow has 3 stages reporting to Prometheus.

We use various backends to leverage caching and facilitate faster reads everywhere.

The retry policy waits 100ms then aborts after 3 retries unless cached.
