# Contributing to `upzi`

The guidelines are fairly simple. We use the latest `zig` version packaged by
GNU Guix.

Development takes place at: https://sl.urutau-ltd.org/urutau-ltd/upzi/

Mirrors are present at:

- [Codeberg](https://codeberg.org/urutau-ltd/upzi)
- [GitHub](https://github.com/urutau-ltd/upzi)

Issues and PR's are accepted in mirrors as well but milestones and versions
are crafted at our forgejo instance. If you wish to contribute, do so in a new
branch based on the latest `vX.X.X-dev`.

## Guix System first

This project is thought and tested on a GNU Guix operating system. Thus, first
class suport is granted for it, as well as `udev` rules, services and more.

Nix may be supported but I'm not experienced enough to package this software
for said distribution

## No LLM Contributions

See the `AGENTS.md` file for more information. In short, we cannot accept PR's
or issues that are written by an LLM due to the uncertain copyright status for
both code and prose themselves.

Please mind, that this only includes the OUTPUTS of an LLM, it doesn't mean you
cannot use one like you would use a search engine or a tutor. However, output
code, partial or total is not accepted. I get it's a tool and that's why it
should aid you, not do the thinking for you.

## Other guidelines

Contributions ideally bring quality of life improvements over features. If you
have a device this tool doesn't support, please extend both `src/hidraw.zig` and
`src/protocol.zig` accordingly.

Follow the zen of zig :)

The library takes precedence over the CLI but don't break the CLI.

That's pretty much it.
