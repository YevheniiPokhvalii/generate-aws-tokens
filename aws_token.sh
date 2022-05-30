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
   # call a function with credentials paths
   select_aws_creds

   # an additional grep is added to colorize the output
   echo "Choose AWS profile: "
   echo "[$AWS_PROFILE] <-- Active profile (empty by default)" | grep "$AWS_PROFILE" --color=always
   aws_profile_before="$AWS_PROFILE"

   # `aws configure list-profiles` is not used because it is slow
   # aws configure list-profiles | grep -v ^${AWS_PROFILE}$ | grep ".*" --color=always || true
   grep -o '^\[.*\]$' "$AWS_CONFIG_FILE" "$AWS_SHARED_CREDENTIALS_FILE" | cut -d ':' -f2- \
   | sed -e 's/[][]//g' -e 's/^profile //g' | awk '!x[$0]++' | grep -v ^${AWS_PROFILE}$ | grep ".*" --color=always || true
   # this `read` is POSIX compatible
   printf 'Skip to use [\e[01;31m'"$AWS_PROFILE"'\e[0m]: '
   read -r active_aws_profile
   case "${active_aws_profile}" in
      *['[]']* ) unset active_aws_profile && echo "ERROR: Special characters are not allowed" ;;
   esac
   if [ ! -z "${active_aws_profile}" ]; then
      export AWS_PROFILE=${active_aws_profile}
   fi

   if [ "${aws_profile_before}" != "${AWS_PROFILE}" ]; then
      unset AWS_ACCESS_KEY_ID
      unset AWS_SECRET_ACCESS_KEY
      unset AWS_SESSION_TOKEN
   fi

   printenv | grep AWS_PROFILE || echo "AWS_PROFILE=$AWS_PROFILE"
}

select_aws_region()
{
   # AWS_REGION=$(aws configure get region) was not used because it does not want to work with other profiles
   if [ ! -n "${AWS_REGION}" ]; then
      AWS_REGION="eu-central-1"
   fi

   printf 'Enter AWS region. Skip to use [\e[01;31m'"$AWS_REGION"'\e[0m]: '
   read -r read_region
   if [ ! -z "${read_region}" ]; then
      AWS_REGION=${read_region}
   fi

   echo "$AWS_REGION" | grep "$AWS_REGION" --color=always
}

update_kube()
{
   # `aws eks list-clusters --profile` does not work after MFA with temporary credentials
   echo "Choose cluster: "
   aws eks list-clusters --region "$AWS_REGION" --output=yaml --query "clusters" | sed 's/- //' | grep ".*" --color=always

   printf 'Enter cluster name: '
   read -r cluster_name
   echo "$cluster_name" | grep "$cluster_name" --color=always

   # `aws eks` does not generate a kubeconfig with the --profile flag after MFA 
   # so the aws_profile function is used during the flag calling.
   # It adds env AWS_PROFILE in the kubeconfig after its generation.
   aws eks --region "$AWS_REGION" update-kubeconfig --name $cluster_name
}

gen_kubeconfig()
{
   kubectl config view --minify --raw
}

config_tmp_profile()
{
   if [ ! -z "${AWS_ACCESS_KEY_ID}" ]; then
      temp_profile_name="MFA-${AWS_PROFILE}-$(date +"%d-%b-%Hh-%Mm-%Ss")"
      printf "\n[profile ${temp_profile_name}]\nregion = ${AWS_REGION}\noutput = json\n" >> "$AWS_CONFIG_FILE"
      printf "\n[${temp_profile_name}]\n" >> "$AWS_SHARED_CREDENTIALS_FILE"
      printf "aws_access_key_id = $AWS_ACCESS_KEY_ID\n" >> "$AWS_SHARED_CREDENTIALS_FILE"
      printf "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY\n" >> "$AWS_SHARED_CREDENTIALS_FILE"
      printf "aws_session_token = $AWS_SESSION_TOKEN\n" >> "$AWS_SHARED_CREDENTIALS_FILE"
      export AWS_PROFILE="$temp_profile_name"
      echo "Temporary MFA profile has been configured: "
      printenv | grep AWS_PROFILE
   else
      echo "The session token has not been generated."
   fi
}

delete_aws_profile()
{
   echo -n "Are you sure you want to delete this profile? (y/n)? "
   read answer
   if [ "$answer" != "${answer#[Yy]}" ]; then
      tmp_aws_config=tmp_aws_conf_"${AWS_PROFILE}"
      tmp_aws_creds=tmp_aws_creds_"${AWS_PROFILE}"

      # `sed -i` works differently on Ubuntu and MacOS so the tmp files were used instead
      awk 'NF' "${AWS_CONFIG_FILE}" | sed -e '/\['"${AWS_PROFILE}"'\]/{N;N;d;}' -e '/\[profile '"${AWS_PROFILE}"'\]/{N;N;d;}' > "$tmp_aws_config"
      mv "$tmp_aws_config" "${AWS_CONFIG_FILE}"

      if [ "${AWS_PROFILE}" != "${AWS_PROFILE/MFA/}" ]; then
         awk 'NF' "${AWS_SHARED_CREDENTIALS_FILE}" | sed '/\['"${AWS_PROFILE}"'\]/{N;N;N;d;}' > "$tmp_aws_creds"
      else
         awk 'NF' "${AWS_SHARED_CREDENTIALS_FILE}" | sed '/\['"${AWS_PROFILE}"'\]/{N;N;d;}' > "$tmp_aws_creds"
      fi
      mv "$tmp_aws_creds" "${AWS_SHARED_CREDENTIALS_FILE}"

      unset AWS_PROFILE
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
   echo "------------------"
   printenv | grep "AWS_SECRET_ACCESS_KEY" | sed -E "s/(.{32})(.{20})/\1**********/" | grep "AWS_SECRET_ACCESS_KEY" || \
   echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
   echo "------------------"
   printenv | grep "AWS_SESSION_TOKEN" | sed -E "s/(.{35})(.{250})/\1**********/"  | grep "AWS_SESSION_TOKEN" || \
   echo "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN"
   echo "------------------"
   printenv | grep "AWS_PROFILE" || echo "AWS_PROFILE=$AWS_PROFILE"
}

print_unmasked_var()
{
   printenv | grep "AWS_ACCESS_KEY_ID" || echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
   echo "------------------"
   printenv | grep "AWS_SECRET_ACCESS_KEY" || echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
   echo "------------------"
   printenv | grep "AWS_SESSION_TOKEN" || echo "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN"
   echo "------------------"
   printenv | grep "AWS_PROFILE" || echo "AWS_PROFILE=$AWS_PROFILE"
}

aws_vars_unset()
{
   echo "Variable unset must be done in the current shell only."
   echo "------------------"
   unset AWS_ACCESS_KEY_ID
   unset AWS_SECRET_ACCESS_KEY
   unset AWS_SESSION_TOKEN
   unset AWS_PROFILE
}

generate_aws_mfa()
{
   echo "Enter MFA code: "
   aws_mfa_device_sn=$(aws iam list-mfa-devices --profile "$AWS_PROFILE" --output=text --query MFADevices[0].SerialNumber)

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
   aws sts get-session-token --serial-number $aws_mfa_device_sn --token-code $aws_mfa_code --profile "$AWS_PROFILE" > $aws_token_file

   if [ ! -z "${aws_mfa_code}" ]; then
      export AWS_ACCESS_KEY_ID=$(grep -o '"AccessKeyId": "[^"]*' $aws_token_file | grep -o '[^"]*$')
      export AWS_SECRET_ACCESS_KEY=$(grep -o '"SecretAccessKey": "[^"]*' $aws_token_file | grep -o '[^"]*$')
      export AWS_SESSION_TOKEN=$(grep -o '"SessionToken": "[^"]*' $aws_token_file | grep -o '[^"]*$')
   fi

   echo "------------------"
   echo "Exported variables:"
   echo "------------------"

   print_masked_var

   if [ -s $aws_token_file ]; then
      echo "------------------"
      echo "The token expires on $(grep -o '\"Expiration\": "[^"]*' $aws_token_file | grep -o '[^"]*$')"
   fi

   rm $aws_token_file
}

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
      select_aws_region
      config_tmp_profile
      return 0
      ;;
   -d|--delete)
      # delete AWS_PROFILE
      select_aws_creds
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
