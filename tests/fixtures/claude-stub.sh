#!/usr/bin/env bash
# Test stub for `claude` binary. Sleeps so the tmux pane stays alive.
case "${1:-}" in
    --version) echo "claude-stub 0.0.0-test"; exit 0 ;;
esac
exec sleep 9999
