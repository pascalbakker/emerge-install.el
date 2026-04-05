# Features

Adds a workflow to easily install emerge packages on Gentoo without having to manually write flags in package.use. It automatically creates a file in your package.use with the proper flags. 

# Installation

Place emerge-install.el in your config folder and load it.

# Workflow

1.
```
M-x emerge-install-package
```
2. select package to install
3. Choose flags to install in I column with RET keybinding
4. C-c C-c
5. Enter in passwords for sudo commands (one to write one to install)

Package will be installed with flags

# Dependencies

equery (app-portage/gentoolkit)

app-portage/eix

emerge

# TODO
1. Handle version conflicts, i.e. etc-update conflicts
2. Handle package masking edge cases
3. Show a temp buffer with flags so user can confirm changes before executing
