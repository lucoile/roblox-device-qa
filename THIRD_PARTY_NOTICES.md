# Third-party software

The original skill documentation and helper scripts in this repository use
the [MIT license](LICENSE). This license does not relicense Rojo or its
dependencies. This project is independent of Roblox and Rojo.

## Optional Rojo helper

Rojo binaries and source modules are not committed to this repository.
`scripts/setup_rojo.py` downloads the official **Rojo 7.7.0** plugin model
and builds an inert copy locally. Generated files stay in the ignored
`assets/` directory.

- [Official release](https://github.com/rojo-rbx/rojo/releases/tag/v7.7.0)
- [Original plugin model](https://github.com/rojo-rbx/rojo/releases/download/v7.7.0/Rojo.rbxm)
- [Corresponding source](https://github.com/rojo-rbx/rojo/tree/v7.7.0/plugin)
- [Upstream license](https://github.com/rojo-rbx/rojo/blob/v7.7.0/LICENSE.txt)

Rojo is copyright its contributors and licensed under the Mozilla Public
License 2.0. A copy is provided in [LICENSES/MPL-2.0.txt](LICENSES/MPL-2.0.txt).
Rojo's dependencies retain their own copyright and license notices in the
upstream source. The MIT license here does not apply to those dependencies.

The transformation is implemented in `scripts/build_rojo.luau`: it preserves
the module sources and hierarchy, while converting executable plugin
entrypoints into inert folders. No upstream ModuleScript source is changed.
The native plugin's UI is not started. This is a pinned integration with
Rojo internals, not an officially supported Rojo API.

The setup script verifies the original release checksum before loading it:

```text
214e5ad84ccdc88f873e0467b6724e4ea9ada8ea340fcb9d4397cb899a67c83f
```

The bootstrap generator accepts only the tested transformed model checksum:

```text
6b6986bec809f6ef6461df1731d49fc1aaa9242c78c2685751c7b1f17f45b9c7
```

When redistributing a generated Rojo model, provide its corresponding
source, transformation instructions, and required upstream notices under
the applicable licenses. The generated model is intentionally excluded
from this repository's source releases.
