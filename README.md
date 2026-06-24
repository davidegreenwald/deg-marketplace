# deg marketplace

A Claude Code plugin marketplace for David Greenwald's plugins. The repo is a catalog only — each plugin lives in its own repository, and `.claude-plugin/marketplace.json` lists them with a pinned version.

## How do I add the marketplace?

```
/plugin marketplace add davidegreenwald/deg-marketplace
```

That registers the marketplace under the name `deg`. Adding it is a one-time step; after that, each plugin installs with a single command.

## Available plugins

### technical-writing-voice

Voice and clarity rules for technical prose — lead with the point, name the mechanism, state the tradeoff, stop. Applied automatically when Claude writes or edits docs, READMEs, explanations, plan files, commit messages, or code comments. Source: [technical-writing-voice](https://github.com/davidegreenwald/technical-writing-voice).

```
/plugin install technical-writing-voice@deg
```

### greenfield

Build and customize a production-ready agent workflow from scratch, or audit and upgrade your existing projects. Run it on an empty directory to scaffold a new project, or on an existing repo to review it against 13 success factors and install only what's missing — decision-complete tickets, a hook-enforced quality gate, reviewer subagents, ADRs, path-scoped rules, and a `/work` command. User-invoked via `/greenfield:greenfield`. Source: [claude-greenfield](https://github.com/davidegreenwald/claude-greenfield).

```
/plugin install greenfield@deg
```

## How do I auto-enable a plugin in a project?

Add the marketplace and enable the plugin in a project's `.claude/settings.json`, and anyone who trusts the folder is prompted to install both:

```json
{
  "extraKnownMarketplaces": {
    "deg": { "source": { "source": "github", "repo": "davidegreenwald/deg-marketplace" } }
  },
  "enabledPlugins": { "technical-writing-voice@deg": true }
}
```

## How does versioning stay current?

Each plugin is pinned to an exact release in its own repo. A plugin entry's `source` carries a `ref` (the `<name>--v<semver>` git tag) and a `sha` (the exact commit), so an install resolves to a known version rather than the moving branch tip.

A scheduled GitHub Actions job (`.github/workflows/sync-pins.yml`) keeps the pins current. It runs `scripts/update-pins.sh`, which reads each github-source entry, finds the newest `<name>--v<semver>` tag in that plugin's repo, and advances `ref` + `sha`. When a pin moves, the job validates the catalog with `claude plugin validate --strict` and opens a pull request — so every catalog change is reviewable, and the sync needs no cross-repo secrets (it uses the default `GITHUB_TOKEN`).

The version itself lives in each plugin's own `plugin.json` and is authoritative; the catalog entry deliberately omits a `version` field and pins by tag instead.

## How do I add a new plugin to this marketplace?

1. Create the plugin in its own public repo (root-layout: `.claude-plugin/plugin.json` plus `skills/`, `commands/`, or `agents/`). Set a semantic `version` in `plugin.json`.
2. Cut a release tag with `claude plugin tag --push`, which creates `<plugin-name>--v<version>`.
3. Add an entry to `plugins[]` in `.claude-plugin/marketplace.json` with a `github` source pointing at the repo and `ref` set to that tag. Leave `sha` out — the sync job fills it in.
4. Bump `metadata.version`, validate with `claude plugin validate --strict .`, and commit. The sync job advances the pin on every later release.

## License

MIT. See `LICENSE`.
