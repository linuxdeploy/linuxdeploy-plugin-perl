# linuxdeploy-plugin-perl

Perl plugin for linuxdeploy. Sets up a [relocatable-perl](https://github.com/skaji/relocatable-perl) environment inside an AppDir, and installs user-specified packages.


## Usage

```bash
# get linuxdeploy and linuxdeploy-plugin-perl (see below for more information)
> [...]
# configure environment variables which control the plugin's behavior
> export CPAN_PACKAGES=mypackage;myotherpackage
# call through linuxdeploy
> ./linuxdeploy-x86_64.AppImage --appdir AppDir --plugin perl --output appimage [...]
```

There are many variables available to alter the behavior of the plugin. The current list can be obtained by calling the plugin with `--help`.

