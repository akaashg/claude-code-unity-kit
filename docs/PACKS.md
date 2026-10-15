# Adding a platform pack

A pack is a plugin in this marketplace that adds platform-specific rules on top of `unity-kit`. Generic Unity rules go in the core; anything tied to one platform, SDK, vendor package or Unity version range goes in a pack.

| Belongs in the core | Belongs in a pack |
|---|---|
| `.meta` safety, compile gate, static reset, project style | Quest build settings, OpenXR package conflicts, Android SDK versions |
| Applies to any Unity 6 project | Applies only when a platform or package is present |

## Steps

1. **Name it `unity-kit-<name>`.** Plugin names starting with `claude-` fail validation.
2. **Create the plugin** at `plugins/unity-kit-<name>/` with `.claude-plugin/plugin.json`:

   ```json
   {
     "name": "unity-kit-quest",
     "version": "0.1.0",
     "description": "Meta Quest rules for unity-kit.",
     "author": { "name": "Your Name" },
     "license": "MIT",
     "dependencies": [
       { "name": "unity-kit", "version": "^0.1.0" }
     ]
   }
   ```

   A bare name resolves in this marketplace. The version range resolves against git tags named `unity-kit--v<version>`, so the core must be tagged that way (`claude plugin tag`).
3. **Add it to `.claude-plugin/marketplace.json`** with `"source": "./plugins/unity-kit-<name>"`. Keep the entry `name` equal to the `plugin.json` name.
4. **Add a `Platform notes` section.** Give the pack an `init` skill that appends a `### <Platform>` section under `## Platform notes` in the project's `CLAUDE.md`, the same way the core `init` writes the file.
5. **Cite sources.** Add each rule to [SOURCES.md](SOURCES.md) with where it came from. Move the item out of [ROADMAP.md](ROADMAP.md).
6. **Validate and test.**

   ```bash
   claude plugin validate --strict plugins/unity-kit-<name>
   claude plugin validate --strict .
   claude --plugin-dir ./plugins/unity-kit --plugin-dir ./plugins/unity-kit-<name>
   ```

   The last command loads both plugins for one session, so the dependency is met without installing.
