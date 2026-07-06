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

### ios verify_app_store_record

```sh
[bundle exec] fastlane ios verify_app_store_record
```

Verify the App Store Connect app record exists

### ios create_app_record

```sh
[bundle exec] fastlane ios create_app_record
```

Register the App ID and create the App Store Connect app record (headless, API-key only)

### ios bootstrap_match

```sh
[bundle exec] fastlane ios bootstrap_match
```

Create or refresh App Store signing assets in the shared match repo (run once per app)

### ios deploy_testflight

```sh
[bundle exec] fastlane ios deploy_testflight
```

Build a signed Release archive and upload it to TestFlight

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Alias for deploy_testflight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
