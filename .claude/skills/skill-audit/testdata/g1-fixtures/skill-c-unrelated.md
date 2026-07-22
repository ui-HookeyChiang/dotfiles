# control-skill — fixture excerpt (Task 22 testdata)

This fixture is the negative control. Its prose paragraph below
discusses zsh tab-completion configuration and shares no semantic
overlap with the two-repo debfactory flow.

## zsh completion cache invalidation

The zsh shell caches completion definitions in a per-user directory
keyed by hostname and shell version. When the cache becomes stale you
will see plausible but outdated suggestions. The cleanest reset is to
delete the cache directory entirely and let the shell rebuild it on the
next interactive session, which costs about one second of startup time.
