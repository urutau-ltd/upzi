# upzi

Libre monitor for Koblenz and compatible UPS devices using the Megatec Q1
protocol over USB HID. Reworked in zig. More specifically
the [Voltronic Power - 'QS' UPS communication protocols](https://networkupstools.org/protocols/voltronic-qs.html)

No proprietary software required, a future version should replace the bundled
`ViewPower` that comes with some of these UPS devices, sadly, said software is
nonfree.

## Supported Hardware

Any UPS whose USB interface identifies as:

```bash
INNO TECH  USB to Serial
```

This (I'm not 100% sure) should include all other brands built on the same
Voltronic/Megatec ODM hardware. Despite it's name, the chip
enumerates as a USB HID device. The OS binds `usbhid` and creates
`/dev/hidrawN`. There is no CDC-ACM serial device. Despite the chip's
marketing name "USB to Serial", from Linux's perspective this is purely HID
and must be accessed via the hidraw API.

## Requirements

- `GNU Guix` (Highly recommended, but optional)
- Linux-Libre or Linux Kernel v3.0 or later
- Zig `v0.16.0` or a `x86_64-linux-gnu` machine.

## Building

We use [maak](https://codeberg.org/jjba23/maak) as the build system for this project.

Run `maak --list` to see all available build targets:

```bash
$ maak --list

--------------------------------------------------------------

Maak 0.12.4: the infinitely extensible command runner

Loading tasks from Maak file: /home/user/src/upzi/maak.scm


--------------------------------------------------------------


build: Build the project executable

build-test: Test if the project compiles

clean: Cleanup build artifacts

default:

test: Run the test suite

```

### Using Guix

You can also build and test this using the provided `guix.scm` to build a
reproducible Guix package:

```bash
$ guix build -f ./guix.scm
```

## Installation

### Manually

### Using Guix

## Testing

## Hacking
