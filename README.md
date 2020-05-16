# gitr-done
This is just a simple pre-run script that makes sure sudo, git, and docker are installed based on the detected Linux distribution, then it clones the given git repository and executes a given script in that cloned repository. This is to help create an environment that is mostly predictable for automation scripts.

# Usage
Use -s to pass arguments to the pre-run script. The first argument is the URL to the git repository. The second agrument is the reletive path to the initilization script in the cloned repository. All arguments after the first two will be passed through to the initilization script.

# Example
```sh -c "$(url=https://raw.githubusercontent.com/ggpwnkthx/gitr-done/master/run.sh; curl -sSL $url || wget $url -O -)" -s https://github.com/ggpwnkthx/gitr-done.git test.sh other=args -to -passthru```

## Explination
In the examples, we're using substitution instead of piping the stdout of the downloader in order to keep the shell interactive. This also has the benefit of allowing the downloader to run prior to sh being called. We prioritze curl since it's more portable, but if that's not available we switch to wget.
