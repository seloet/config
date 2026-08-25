# Vendored LocalAssistant source

This directory contains the runtime and Nix packaging files from
`seloet/local-assistant` commit `f2b4c9b`.

It is vendored so the shared configuration flake evaluates on hosts that do
not have a separate LocalAssistant checkout. The workstation profile still
enables the service only for hosts that set `localAssistant = true`.
