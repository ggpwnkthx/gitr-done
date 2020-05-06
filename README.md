# gitr-done
This is just a very simple pre-run script that makes sure basic prerequisites are installed based on the detected Linux distribution then clones a given git repository and executes a given script in the cloned repository.

# Usage
Use -s to pass arguments to the pre-run script. The first argument is the URL to the git repository. The second agrument is the reletive path to the initilization script in the cloned repository. All arguments after the first two will be passed through to the initilization script.

# Examples

## wget
```sh -c $(wget -O - https://raw.githubusercontent.com/ggpwnkthx/gitr-done/master/run.sh) -s https://github.com/user/repo init-file other=args -to -passthru```

## curl
```sh -c $(curl -sSL https://raw.githubusercontent.com/ggpwnkthx/gitr-done/master/run.sh) -s https://github.com/user/repo rel/path/to/init.sh other args to passthru```

## Explination
In the examples, we're using substitution instead of piping the stdout of the downloader in order to keep the shell interactive just in case that's needed for the initilization script. This also has the benefit of allowing the downloader to run prior to sh being called.
