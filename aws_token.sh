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

aws_unset()
{
   echo "Variable unset must be done in the current shell only."
   echo "------------------"
   unset AWS_ACCESS_KEY_ID
   unset AWS_SECRET_ACCESS_KEY
   unset AWS_SESSION_TOKEN
   unset AWS_PROFILE
}

select_aws_profile(){
   # an additional grep is added to colorize the output
   echo "Choose AWS profile: "
   echo "[$AWS_PROFILE] <-- Active profile (empty by default)" | grep "$AWS_PROFILE" --color=always
   aws_profile_before="$AWS_PROFILE"

   if [ ! -n "${AWS_CONFIG_FILE}" ]; then
      AWS_CONFIG_FILE=~/.aws/config
   fi

   # `aws configure list-profiles` is not used because it is slow
   # aws configure list-profiles | awk '!/^'"$AWS_PROFILE"'$/' | grep ".*" --color=always || true
   # `grep -xv "$AWS_PROFILE"` was replaced by `awk '!/^'"$AWS_PROFILE"'$/'` for better compatibility
   grep -o '\[.*]' "$AWS_CONFIG_FILE" | sed 's/[][]//g' | sed 's/profile //g' | awk '!/^'"$AWS_PROFILE"'$/' | grep ".*" --color=always || true
   # this `read` is POSIX compatible
   printf 'Skip to use [\e[01;31m'"$AWS_PROFILE"'\e[0m]: '
   read -r active_aws_profile
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

select_aws_creds()
{
   if [ ! -n "${AWS_CONFIG_FILE}" ]; then
      AWS_CONFIG_FILE=~/.aws/config
   fi
   if [ ! -n "${AWS_SHARED_CREDENTIALS_FILE}" ]; then
      AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials
   fi
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
      printf "\n[${temp_profile_name}]\nregion = ${AWS_REGION}\noutput = json\n" >> "$AWS_CONFIG_FILE"
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
      sed -i '$!{/^$/d}' "${AWS_CONFIG_FILE}"
      sed -i '$!{/^$/d}' "${AWS_SHARED_CREDENTIALS_FILE}"
      sed -i '/\['"${AWS_PROFILE}"'\]/{N;N;d;}' "${AWS_CONFIG_FILE}"

      if [ "${AWS_PROFILE}" != "${AWS_PROFILE/MFA/}" ]; then
         sed -i '/\['"${AWS_PROFILE}"'\]/{N;N;N;d;}' "${AWS_SHARED_CREDENTIALS_FILE}"
      else
         sed -i '/\['"${AWS_PROFILE}"'\]/{N;N;d;}' "${AWS_SHARED_CREDENTIALS_FILE}"
      fi
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

# Unsource the script to avoid bugs with the script flags.
# This function solves this problem by replacing the user shell after the script has been sourced with flags.
# It checks whether the script is sourced or not and replaces the shell.
# The check is necessary in order not to invoke redundant shell processes.
# It is added after each flag. 
# Note: $0 does not change after being sourced in zsh unlike bash; hence, it requires a different check.
#
replace_shell(){
   if [ -n "$ZSH_EVAL_CONTEXT" ]; then 
      case $ZSH_EVAL_CONTEXT in *:file*) exec zsh;; esac
   else
      case ${0##*/} in sh|dash|bash) exec bash;; esac
   fi
}

while getopts ":hcugoptd" option; do
   case $option in
      h) # display Help
         help
         replace_shell
         return;;
         # exit;;
      c) # uset aws token variables
         aws_unset
         print_masked_var
         replace_shell
         return;;
         # exit;;
      u) # update kubeconfig file
         select_aws_profile
         select_aws_region
         update_kube
         replace_shell
         return;;
         # exit;;
      g) # generate kubeconfig
         gen_kubeconfig
         replace_shell
         return;;
         # exit;;
      o) # check unmasked aws variables
         print_unmasked_var
         replace_shell
         return;;
         # exit;;
      p) # change AWS_PROFILE
         select_aws_profile
         replace_shell
         return;;
         # exit;;
      t) # configure tmp AWS_PROFILE
         select_aws_creds
         select_aws_region
         config_tmp_profile
         replace_shell
         return;;
         # exit;;
      d) # delete AWS_PROFILE
         select_aws_creds
         select_aws_profile
         delete_aws_profile
         replace_shell
         return;;
         # exit;;
     \?) # Invalid option
         echo "Error: Invalid option"
         echo "Use './script -h' for help"
         replace_shell
         return;;
         # exit;;
   esac
done

select_aws_profile

echo "Enter MFA code: "
aws_mfa_account=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --output=text --query "Arn" | sed 's/user/mfa/')
read aws_mfa_code

aws_token_file="session-token-$aws_mfa_code.json"

# The credentials duration for IAM user sessions is 43,200 seconds (12 hours) as the default.
# Alternative: the session token can be saved in a separate [aws_mfa_code] AWS profile to use it across shells.
# aws sts get-session-token --serial-number $aws_mfa_account --token-code $aws_mfa_code --profile "$AWS_PROFILE" \
# --output=yaml --query "Credentials.{aws_access_key_id: AccessKeyId, aws_secret_access_key: SecretAccessKey, aws_session_token: SessionToken}"
aws sts get-session-token --serial-number $aws_mfa_account --token-code $aws_mfa_code --profile "$AWS_PROFILE" > $aws_token_file

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

rm -rf $aws_token_file

replace_shell
