#!/bin/sh

help()
{
   # Display Help
   echo "This script must be sourced"
   echo "in order to get the variables working."
   echo "Example: 'source ./script' or '. ./script' "
   echo
   echo "Syntax: ./script [-h|c|u|g|o|p|t|d]"
   echo "options:"
   echo "h     Print Help."
   echo "c     Unset variables."
   echo "u     Update the kubeconfig file."
   echo "g     Generate kubeconfig for the current context."
   echo "o     Print the current unmasked AWS variables."
   echo "p     Switch AWS_PROFILE."
   echo "t     Generate temporary MFA AWS_PROFILE."
   echo "d     Delete temporary MFA AWS_PROFILE."
   echo
}

select_aws_creds()
{
   if [ ! -n "${AWS_CONFIG_FILE}" ]; then
      AWS_CONFIG_FILE=~/.aws/config
   fi
   if [ ! -n "${AWS_SHARED_CREDENTIALS_FILE}" ]; then
      AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials
   fi
}

select_aws_profile()
{
   # call the function with credentials paths
   select_aws_creds

   # The initial profile value
   aws_profile_before="$AWS_PROFILE"

   # escape special characters for the initial profile value
   aws_profile_esc="$(printf '%s' "$AWS_PROFILE" | sed -e 's`[][\\/.*^$]`\\&`g')"

   # An additional grep is added to colorize the output.
   echo "Choose AWS profile: "
   printf '%s\n' "[$(printf '%s' "$AWS_PROFILE" | grep '.*' --color=always)] <-- Active profile (empty by default)"
   # `aws configure list-profiles` is not used because it is slow
   # aws configure list-profiles | grep -v "^${aws_profile_esc}$" | grep '.*' --color=always || true
   grep -o '^\[.*\]$' "$AWS_CONFIG_FILE" "$AWS_SHARED_CREDENTIALS_FILE" | cut -d ':' -f2- \
   | sed -e 's/[][]//g' -e 's/^profile //g' | awk '!x[$0]++' | grep -v "^${aws_profile_esc}$" | grep '.*' --color=always || true

   # This `read` and `printf` are POSIX compliant.
   printf '%s' "Skip to use [$(printf '%s' "$AWS_PROFILE" | grep '.*' --color=always)]: "
   read -r active_aws_profile
   case "${active_aws_profile}" in
      *['[]']* ) unset active_aws_profile && echo "ERROR: Special characters are not allowed" ;;
   esac
   if [ ! -z "${active_aws_profile}" ]; then
      export AWS_PROFILE="${active_aws_profile}"
      aws_profile_esc="$(printf '%s' "$AWS_PROFILE" | sed -e 's`[][\\/.*^$]`\\&`g')"
   fi

   if [ "${aws_profile_before}" != "${AWS_PROFILE}" ]; then
      unset AWS_ACCESS_KEY_ID
      unset AWS_SECRET_ACCESS_KEY
      unset AWS_SESSION_TOKEN
   fi

   printenv | grep "AWS_PROFILE" || echo "AWS_PROFILE=$AWS_PROFILE"
}

# This function should be called after choosing an AWS profile
select_aws_region()
{
   # `aws configure get region` does not work with old profiles that did not have the 'profile' prefix in the AWS config file.
   # `aws_profile_esc` escape special characters (taken from the AWS profile function).
   # The solution for profiles with the old naming convention:
   aws_region_old_profile="$(cat "${AWS_CONFIG_FILE}" | sed -n '/^\['"$aws_profile_esc"'\]$/,/^\[/p' | grep '^region' | awk '{ print $3 }')"

   aws_profile_region="$(aws configure get region || printf '%s' "$aws_region_old_profile")"

   # AWS cli region variable precedence. Can be checked with `aws configure list`.
   if [ ! -z "${AWS_REGION}" ]; then
      aws_profile_region="$AWS_REGION"
   elif [ ! -z "${AWS_DEFAULT_REGION}" ]; then
      aws_profile_region="$AWS_DEFAULT_REGION"
   elif [ ! -n "${aws_profile_region}" ]; then
      aws_profile_region='eu-central-1'
   fi

   printf '%s' "Enter AWS region. Skip to use [$(printf '%s' "$aws_profile_region" | grep '.*' --color=always)]: "
   read -r read_region
   if [ ! -z "${read_region}" ]; then
      aws_profile_region="${read_region}"
   fi

   printf '%s' "$aws_profile_region" | grep '.*' --color=always
}

update_kube()
{
   # `aws eks list-clusters --profile` does not work after MFA with temporary credentials
   echo "Choose cluster: "
   aws eks list-clusters --region "$aws_profile_region" --output=yaml --query "clusters" | sed 's/- //' | grep '.*' --color=always

   printf 'Enter cluster name: '
   read -r cluster_name
   printf '%s' "$cluster_name" | grep '.*' --color=always

   # `aws eks` does not generate a kubeconfig with the --profile flag after MFA 
   # so the aws_profile function is used during the flag calling.
   # It adds env AWS_PROFILE in the kubeconfig after its generation.
   aws eks --region "$aws_profile_region" update-kubeconfig --name "$cluster_name"
}

gen_kubeconfig()
{
   kubectl config view --minify --raw
}

config_tmp_profile()
{
   if [ "${AWS_PROFILE}" != "${AWS_PROFILE/MFA/}" ]; then
      printenv | grep "AWS_PROFILE"
      echo "WARNING: Do not run the script for a temporary profile"
   elif [ ! -z "${AWS_ACCESS_KEY_ID}" ]; then
      # Calling the function to choose a region. It is implied here that an AWS profile is already selected.
      select_aws_region

      temp_profile_name="MFA-${AWS_PROFILE}-$(date +"%d-%b-%Hh-%Mm-%Ss")"

      printf '\n%s\n' "[profile ${temp_profile_name}]" >> "$AWS_CONFIG_FILE"
      printf '%s\n' "region = ${aws_profile_region}" >> "$AWS_CONFIG_FILE"
      printf '%s\n' "output = json" >> "$AWS_CONFIG_FILE"
      
      printf '\n%s\n' "[${temp_profile_name}]" >> "$AWS_SHARED_CREDENTIALS_FILE"
      printf '%s\n' "aws_access_key_id = $AWS_ACCESS_KEY_ID" >> "$AWS_SHARED_CREDENTIALS_FILE"
      printf '%s\n' "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY" >> "$AWS_SHARED_CREDENTIALS_FILE"
      printf '%s\n' "aws_session_token = $AWS_SESSION_TOKEN" >> "$AWS_SHARED_CREDENTIALS_FILE"

      export AWS_PROFILE="$temp_profile_name"
      echo "$print_dashes"
      echo "Temporary MFA profile has been configured: "
      printenv | grep "AWS_PROFILE"
   else
      select_aws_profile
      generate_aws_mfa
      if [ ! -z "${AWS_ACCESS_KEY_ID}" ]; then
         config_tmp_profile
      fi
   fi
}

# This function should be called after choosing an AWS profile
delete_aws_profile()
{
   printf '%s' "Are you sure you want to delete this profile? (y/n)? "
   read answer
   if [ "$answer" != "${answer#[Yy]}" ]; then
      tmp_aws_config='tmp_aws_conf'

      # `sed -i` works differently on Ubuntu and MacOS so the tmp files were used instead.
      # `aws_profile_esc` escape special characters (taken from the AWS profile function).
      awk 'NF' "${AWS_CONFIG_FILE}" | sed -e '/^\['"$aws_profile_esc"'\]$/,/^\[/{//!d;}' -e '/^\['"$aws_profile_esc"'\]$/{d;}' \
      | sed -e '/^\[profile '"$aws_profile_esc"'\]$/,/^\[/{//!d;}' -e '/^\[profile '"$aws_profile_esc"'\]$/{d;}'  > "$tmp_aws_config"
      mv "$tmp_aws_config" "${AWS_CONFIG_FILE}"

      awk 'NF' "${AWS_SHARED_CREDENTIALS_FILE}" | sed -e '/^\['"$aws_profile_esc"'\]$/,/^\[/{//!d;}' -e '/^\['"$aws_profile_esc"'\]$/{d;}' > "$tmp_aws_config"
      mv "$tmp_aws_config" "${AWS_SHARED_CREDENTIALS_FILE}"

      unset AWS_PROFILE
      unset AWS_ACCESS_KEY_ID
      unset AWS_SECRET_ACCESS_KEY
      unset AWS_SESSION_TOKEN
      echo "AWS_PROFILE=$AWS_PROFILE"
   else
      echo "Skipped..."
   fi
}

print_masked_var()
{
   # an additional grep is used to preserve the colors of a variable state
   # another echo is used to visualize the case when variables are not set
   # {255} is the BSD sed limit (MacOS)
   printenv | grep "AWS_ACCESS_KEY_ID" | sed -E "s/(.{23})(.{10})/\1**********/" | grep "AWS_ACCESS_KEY_ID" || \
   echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
   echo "$print_dashes"
   printenv | grep "AWS_SECRET_ACCESS_KEY" | sed -E "s/(.{32})(.{20})/\1**********/" | grep "AWS_SECRET_ACCESS_KEY" || \
   echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
   echo "$print_dashes"
   printenv | grep "AWS_SESSION_TOKEN" | sed -E "s/(.{35})(.{250})/\1**********/"  | grep "AWS_SESSION_TOKEN" || \
   echo "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN"
   echo "$print_dashes"
   printenv | grep "AWS_PROFILE" || echo "AWS_PROFILE=$AWS_PROFILE"
}

print_unmasked_var()
{
   printenv | grep "AWS_ACCESS_KEY_ID" || echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
   echo "$print_dashes"
   printenv | grep "AWS_SECRET_ACCESS_KEY" || echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
   echo "$print_dashes"
   printenv | grep "AWS_SESSION_TOKEN" || echo "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN"
   echo "$print_dashes"
   printenv | grep "AWS_PROFILE" || echo "AWS_PROFILE=$AWS_PROFILE"
}

aws_vars_unset()
{
   echo "Variable unset must be done in the current shell only."
   echo "$print_dashes"
   unset AWS_ACCESS_KEY_ID
   unset AWS_SECRET_ACCESS_KEY
   unset AWS_SESSION_TOKEN
   unset AWS_PROFILE
}

generate_aws_mfa()
{
   echo "Enter MFA code: "
   aws_mfa_device_sn="$(aws iam list-mfa-devices --profile "$AWS_PROFILE" --output=text --query "MFADevices[0].SerialNumber")"

   if [ ! -n "${aws_mfa_device_sn}" ] || [ "${aws_mfa_device_sn}" = "None" ]; then
      echo "WARNING: There is no MFA device assigned to this profile"
      return 1
   fi

   read aws_mfa_code
   aws_token_file="session-token-$aws_mfa_code.json"

   # The credentials duration for IAM user sessions is 43,200 seconds (12 hours) as the default.
   # Alternative: the session token can be saved in a separate [aws_mfa_code] AWS profile to use it across shells.
   # aws sts get-session-token --serial-number $aws_mfa_device_sn --token-code $aws_mfa_code --profile "$AWS_PROFILE" \
   # --output=yaml --query "Credentials.{aws_access_key_id: AccessKeyId, aws_secret_access_key: SecretAccessKey, aws_session_token: SessionToken}"
   aws sts get-session-token --serial-number "$aws_mfa_device_sn" --token-code "$aws_mfa_code" --profile "$AWS_PROFILE" > "$aws_token_file"

   if [ ! -z "${aws_mfa_code}" ]; then
      export AWS_ACCESS_KEY_ID="$(grep -o '"AccessKeyId": "[^"]*' "$aws_token_file" | grep -o '[^"]*$')"
      export AWS_SECRET_ACCESS_KEY="$(grep -o '"SecretAccessKey": "[^"]*' "$aws_token_file" | grep -o '[^"]*$')"
      export AWS_SESSION_TOKEN="$(grep -o '"SessionToken": "[^"]*' "$aws_token_file" | grep -o '[^"]*$')"
   fi

   echo "$print_dashes"
   echo "Exported variables:"
   echo "$print_dashes"

   print_masked_var

   if [ -s "$aws_token_file" ]; then
      echo "$print_dashes"
      echo "The token expires on $(grep -o '\"Expiration\": "[^"]*' "$aws_token_file" | grep -o '[^"]*$')"
      echo "$print_dashes"
   fi

   rm "$aws_token_file"
}

print_dashes="$(printf '%.0s-' {1..20}; echo)"

# This loop is used instead of `getopts`, since `getopts` is inconsistent when sourcing a script in different shells.
# `getopts` relies on the `OPTIND` variable (OPTIND=1 by default) and that variable works differently in bash and zsh.
# While `getopts` can be fixed in bash by setting `OPTIND=1`, 
# zsh also requires additional manipulations like a shell replacement with `exec zsh`.
while [ "$#" -gt 0 ]
do
   case "$1" in
   -h|--help)
      # display Help
      help
      return 0
      ;;
   -c|--clear)
      # uset aws token variables
      aws_vars_unset
      print_masked_var
      return 0
      ;;
   -u|--update)
      # update kubeconfig file
      select_aws_profile
      select_aws_region
      update_kube
      return 0
      ;;
   -g|--generate)
      # generate kubeconfig
      gen_kubeconfig
      return 0
      ;;
   -o|--output)
      # check unmasked aws variables
      print_unmasked_var
      return 0
      ;;
   -p|--profile)
      # change AWS_PROFILE
      select_aws_profile
      return 0
      ;;
   -t|--temporary)
      # configure tmp AWS_PROFILE
      select_aws_creds
      config_tmp_profile
      return 0
      ;;
   -d|--delete)
      # delete AWS_PROFILE
      select_aws_profile
      delete_aws_profile
      return 0
      ;;
   --)
      break
      ;;
   -*)
      echo "Invalid option '$1'. Use -h|--help to see the valid options" >&2
      return 1
      ;;
   *)
      echo "Invalid option '$1'. Use -h|--help to see the valid options" >&2
      return 1
   ;;
   esac
   shift
done

select_aws_profile
generate_aws_mfa
