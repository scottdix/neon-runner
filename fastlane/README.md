fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios prep

```sh
[bundle exec] fastlane ios prep
```

Provision signing + create ASC app record

### ios register_id

```sh
[bundle exec] fastlane ios register_id
```

Register the bundle ID via Connect API (produce needs an Apple ID; this doesn't)

### ios make_profile

```sh
[bundle exec] fastlane ios make_profile
```

Create + install the App Store provisioning profile

### ios ship

```sh
[bundle exec] fastlane ios ship
```

Archive + upload to TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
