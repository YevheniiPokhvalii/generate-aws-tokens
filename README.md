# The script for generating AWS tokens and updating a kubeconfig file

> Replace `user_email@gmail.com` in the script with your email address<br>

This script should be sourced in order to get the variables working in the current shell.<br>
Example: `source script.sh` or `. script.sh`<br>

Without flags, this script generates AWS tokens for the chosen AWS profile.<br>
Flag `-c` unsets the following variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`<br>
Flag `-u` updates a `kubeconfig` file<br>
Flag `-p` switches between AWS profiles (`AWS_PROFILE` variable)<br>

Flags that do not require sourcing (you can run them via `./script.sh` or `sh ./script.sh`):
Flag `-g` generates a kubeconfig file for the current context<br>
Flag `-o` prints the current unmasked AWS variables<br>

> Bugs: sometimes flags do not work properly with sourcing. Solution: re-run the script in a new shell.<br>
