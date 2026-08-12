# Security Policy

## Reporting a Vulnerability

This project is for **educational reverse-engineering research** on software you
own or are authorized to modify. It does not store user data and has no network
surface.

If you still find a security issue (e.g. in build tooling or the release
process), please **do not open a public issue**. Report it privately:

- Open a [private security advisory](https://github.com/antisali996-dot/5eplay-noads/security/advisories/new)
- Or email the maintainer via GitHub profile

You will receive an acknowledgement within 7 days.

## Scope

- The dylib source in `src/`
- The build & verification tooling (`build.cmd`, `tools/check_macho.py`, CI)
- The release artifacts

## Non-Scope

- The behavior of third-party apps this plugin targets (5EPlay)
- Jailbreak / sideloading environments themselves
