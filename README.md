# upzi - UPS Power Zig Indicator

Libre monitor + CLI for Koblenz and compatible UPS devices using the Voltronic
QS protocol over USB HID. Reworked in zig. More specifically the
[Voltronic Power - 'QS' UPS communication protocols](https://networkupstools.org/protocols/voltronic-qs.html)

No proprietary software required, a future version should replace the bundled
`ViewPower` that comes with some of these UPS devices, sadly, said software is
nonfree.

Also, read the `AGENTS.md` file before screeching at this project please. 0 LLM
code was used to craft this project.

## Supported Hardware

Any UPS whose USB interface identifies as:

```bash
INNO TECH  USB to Serial
```

This (I'm not 100% sure) should include all other brands built on the same
Voltronic/Megatec ODM hardware. Despite it's name, the chip enumerates as a USB
HID device. The OS binds `usbhid` and creates `/dev/hidrawN`. There is no
CDC-ACM serial device. Despite the chip's marketing name "USB to Serial", from
Linux's perspective this is purely HID and must be accessed via the hidraw API.

For now, since `v0.1.0` I have tested it on a `0665:5161 INNO TECH/Cypress` UPS
that supports the QS dialect and have been daily-driving it since.

## Requirements

- `GNU Guix` (Highly recommended, but optional)
- Linux-Libre or Linux Kernel v3.0 or later
- Zig `v0.16.0` on a `x86_64-linux-gnu` machine.

## Usage

```bash
$ upzi --help
usage: upzi [OPTIONS] [ARGS]

options:

  --list, -l          list discoverable UPS devices.
  --json              print the UPS status as JSON once, then exit.
  --once, -o          print the UPS status once, then exit.
  --verbose, -vv      enable verbose output.
  --version, -v       print the version and exit.
  --help, -h          print this help screen and exit.

 Exit code 0 if everything ran successfully. 1 if there's a runtime/device
 failure.

```

### As a library

1. Fetch the package using zig:

```bash
# For latest zig on guix
$ zig fetch --save git+https://sl.urutau-ltd.org/urutau-ltd/upzi

## Mirror 1
$ zig fetch --save git+https://codeberg.org/urutau-ltd/upzi

## Mirror 2
$ zig fetch --save git+https://github.com/urutau-ltd/upzi
```

2. Edit your `build.zig`:

```zig
const upzi_dep = b.dependency("upzi", .{});
exe.root_module.addImport("upzi", upzi_dep.module("upzi"));
```

3. Build your own:

```zig
const upzi = @import("upzi");

// 8<---- trimmed code ----

const path = try upzi.hidraw.discoverUPS(allocator,io);
defer allocator.free(path);

const fd = try upzi.hidraw.openDevice(path);
defer _ = upzi.hidraw.closeDevice(fd) catch {};

const status = try upzi.ups.query(fd);
```

Until zig gets the stable docs viewer, the code is the documentation.

## Building

We use [maak](https://codeberg.org/jjba23/maak) as the build system for this
project.

Run `maak --list` to see all available build targets:

```bash
$ maak --list

--------------------------------------------------------------

build: Build the project executable

build-test: Test if the project compiles

clean: Cleanup build artifacts

default: build-test

test: Run the test suite
```

### Using Guix

You can also build and test this using the provided `guix.scm` to build a
reproducible Guix package:

```bash
$ guix build -f ./guix.scm
```

### Manually

Run the `zig build` commands present at `maak` as you normally would do on any
zig project.

## Installation

### Manually

Run the following:

```bash
# 1. Build the project using maak
$ maak build

# 1.1 If you don't have maak, use zig
$ zig build -Doptimize=ReleaseSafe

# 2. Install and enjoy :)
$ install -Dm755 zig-out/bin/upzi ~/.local/bin

# 3. Make sure ~/.local/bin/ is in your $PATH
```

### Using Guix

Move the `guix.scm` package definition into your own declarative configuration
or install imperatively with:

```bash
# Not recommended!
$ guix install -f ./guix.scm
```

## Testing

Either run `maak test` or `zig build test --summary all`

## Hacking

See [CONTRIBUTING](./CONTRIBUTING.md) for more information.
