#!/usr/bin/env bash

# Runs on a remote node, as the unprivileged user, after `claude` is on PATH.
# Installs Superpowers (the default workflow plugin) plus any extras listed
# in ADDITIONAL_CLAUDE_PLUGINS (newline-separated, "<marketplace> <plugin@marketplace>"
# per line).
#
# Plugin install failures are non-fatal: a transient marketplace error or a
# typo in ADDITIONAL_CLAUDE_PLUGINS shouldn't block the rest of node setup
# (e.g. repo clone). Failures are logged as warnings via `|| echo` rather
# than aborting.

set -u

export PATH="$HOME/.local/bin:$PATH"

install_plugin() {
    local marketplace="$1"
    local plugin="$2"
    claude plugin marketplace add "$marketplace" || echo "warn: failed to add marketplace $marketplace"
    claude plugin install "$plugin" || echo "warn: failed to install plugin $plugin"
}

install_plugin "obra/superpowers-marketplace" "superpowers@superpowers-marketplace"

while IFS=' ' read -r marketplace plugin; do
    [[ -z "$marketplace" ]] && continue
    if [[ -z "$plugin" ]]; then
        echo "warn: skipping malformed entry '$marketplace' (no plugin specified)"
        continue
    fi
    echo "Installing extra plugin: $plugin (from $marketplace)"
    install_plugin "$marketplace" "$plugin"
done <<< "${ADDITIONAL_CLAUDE_PLUGINS:-}"
