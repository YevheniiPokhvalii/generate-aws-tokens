# The script for generating AWS tokens, working with AWS profiles, and updating a kubeconfig file

**Goals**: at the time of writing, the current version of `aws-cli/2.7.7` does not have a convenient way to work with AWS profiles, specifically with temporary AWS profiles and tokens. This script aims to improve this experience.<br>
The script is intended to be POSIX compliant. It was analyzed with [ShellCheck](https://www.shellcheck.net/) and [shfmt](https://github.com/mvdan/sh).<br>
**Related issues**:<br>
https://github.com/aws/aws-cli/issues/6979<br>
https://github.com/aws/aws-cli/issues/6980<br>
https://github.com/aws/aws-cli/issues/3346<br>
**Docs**:<br>
https://aws.amazon.com/premiumsupport/knowledge-center/authenticate-mfa-cli/<br>
https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html<br>

**Prerequisites**: `aws-cli` >= v1.20.x or >= v2.7.x, generated AWS profile with `aws configure`, `kubectl`<br>

> This script must be sourced in order to get the variables working in the current shell.<br>
Example: `source script.sh` or `. script.sh`<br>

* By default (without flags), this script generates AWS tokens for the chosen AWS profile.<br>
* Flag `-c` unsets the following variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`.<br>
* Flag `-u` updates a `kubeconfig` file so that you can connect to an Amazon EKS cluster.<br>
* Flag `-g` displays a `kubeconfig` file for the current context (can be used for Lens).<br>
* Flag `-o` prints the current unmasked AWS variables.<br>
* Flag `-p` switches between AWS profiles (`AWS_PROFILE` variable).<br>
* Flag `-t` configures a temporary MFA AWS profile that can be used across shells. This temporary MFA profile does not depend on the token shell variables. However, since it is added to the `AWS_CONFIG_FILE` and `AWS_SHARED_CREDENTIALS_FILE`, it should be removed from the files manually or you can try the flag `-d`. The default location: `~/.aws/config` and `~/.aws/credentials`.<br>
* Flag `-d` removes an AWS profile from the configuration files indicated in `AWS_CONFIG_FILE` and `AWS_SHARED_CREDENTIALS_FILE`. The default location: `~/.aws/config` and `~/.aws/credentials`. Be careful with this flag. The backup of you current `~/.aws/config` and `~/.aws/credentials` is recommended.

> If you receive `(AccessDeniedException)` error during token generation for an empty profile, try to regenerate tokens or unset the token variables before generating new ones.<br>
If you receive `(AccessDeniedException)` error while running the script with the flag `-u`, don't forget to generate tokens first - run the script without flags.<br>
If an incorrect profile name is indicated by mistake, just re-run the script and enter the correct profile name, or unset the profile variables with the `-c` flag.
