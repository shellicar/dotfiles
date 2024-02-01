# dotfiles

shellicar's Dotfiles

I clone this into my home directory.

e.g.: ~/dotfiles

## Setup

`link.sh` is a helper script to symlink files to your home directory.

If a file already exists, it will not overwrite it.

## tmux

### .tmux-shell

Script to start up a tmux shell from a VS Code directory.

This ensures that the terminal in each project is self contained.

### .prompt

Uses some shell magic to improve the tmux shell.

Updates the shell status to include a `?` (running) `O` (success) or `X` (failure) depending on the exit code of the command.

This is disaplyed in the tmux window.

### bin/pbcopy

Only needed for windows using WSL2. Mouse mode is enabled in tmux, and pipes into `pbcopy`.

Should work out of the box for linux and OSX.

## General

### .vimrc

While I use vim, I don't use it as my primary editor/IDE any longer.

### .functions

`tmuxa` will attach to a tmux session based on a pattern.

e.g.: `tmuxa bh` will attach to the first session that contains the letters 'bh'.

### .dockerfunc

Some (probably out of date) helper commands.

### .profile

Standard script loaded by the shell to source the other files.
