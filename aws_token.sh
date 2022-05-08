#!/bin/sh

help()
{
   # Display Help
   echo "This script must be sourced"
   echo "in order to get the variables working."
   echo "Example: 'source $0' or '. $0' "
   echo
   echo "Syntax: $0 [-h|c|u|g|o|p]"
   echo "options:"
   echo "h     Print Help."
   echo "c     Unset variables."
   echo "u     Update the kubeconfig file."
   echo "g     Generate kubeconfig for the current context"
   echo "      can be run in 'sh'."
   echo "o     Print the current unmasked AWS variables"
   echo "      can be run in 'sh'."
   echo "p     Switch AWS_PROFILE."
   echo
}

aws_unset()
{
   echo "Variable unset must be done in the current shell only."
   echo "Run 'source $0'"
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
   grep -o '\[.*]' ~/.aws/config | sed 's/[][]//g' | grep -xv "$AWS_PROFILE" | grep ".*" --color=always || true
   read -p "Skip to use [$AWS_PROFILE]: " active_aws_profile
   active_aws_profile=${active_aws_profile:-$AWS_PROFILE}
   export AWS_PROFILE=$active_aws_profile

   if [ ! -n "${AWS_PROFILE}" ]
   then
      unset AWS_PROFILE
   fi

   printenv | grep AWS_PROFILE || echo "AWS_PROFILE=$AWS_PROFILE"
}

select_aws_account(){
   read -p "Enter AWS account ID. Skip to use [0000000000000-replace-me]: " account_id
   account_id=${account_id:-0000000000000-replace-me}
   echo $account_id | grep $account_id --color=always
   # Uncomment if you need to use various emails
   # read -p "Enter AWS user email. Skip to use [user_email@gmail.com]: " aws_user_email
   # aws_user_email=${aws_user_email:-user_email@gmail.com}
   # echo $aws_user_email | grep $aws_user_email --color=always
}

update_kube()
{
   echo "Enter the cluster name"
   read cluster_name
   read -p "Enter AWS region. Skip to use [aws-region-replace-me]: " region
   region=${region:-aws-region-replace-me}
   echo $region | grep $region --color=always
   # TODO: export AWS_REGION=$region
   aws eks --region $region update-kubeconfig --name $cluster_name --profile "$AWS_PROFILE"
}

gen_kubeconfig()
{
   kubectl config view --minify --raw
}

print_masked_var()
{
   # an additional grep is used to preserve the colors of a variable state
   # another echo is used to visualize the case when variables are not set
   printenv | grep "AWS_ACCESS_KEY_ID" | sed -r "s/(.{23}).{10}/\1**********/" | grep "AWS_ACCESS_KEY_ID" || \
   echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
   echo "------------------"
   printenv | grep "AWS_SECRET_ACCESS_KEY" | sed -r "s/(.{32}).{20}/\1**********/" | grep "AWS_SECRET_ACCESS_KEY" || \
   echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
   echo "------------------"
   printenv | grep "AWS_SESSION_TOKEN" | sed -r "s/(.{35}).{650}/\1**********/"  | grep "AWS_SESSION_TOKEN" || \
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

while getopts ":hcugop" option; do
   case $option in
      h) # display Help
         help
         return;;
         # exit;;
      c) # uset aws token variables
         aws_unset
         print_masked_var
         return;;
         # exit;;
      u) # update kubeconfig file
         select_aws_profile
         update_kube
         return;;
         # exit;;
      g) # generate kubeconfig
         # this can be run in 'sh'
         gen_kubeconfig
         return;;
         # exit;;
      o) # check unmasked aws variables
         # this can be run in 'sh'
         print_unmasked_var
         return;;
         # exit;;
      p) # change AWS_PROFILE
         select_aws_profile
         return;;
         # exit;;
     \?) # Invalid option
         echo "Error: Invalid option"
         echo "Use '$0 -h' for help"
         return;;
         # exit;;
   esac
done

select_aws_profile
select_aws_account

echo "Enter MFA code"
read mfa

# Comment out the aws_user_email if you need to use different emails from the select_aws_account function
aws_user_email=user_email@gmail.com
filename="session-token-$mfa.json"

aws sts get-session-token --serial-number arn:aws:iam::$account_id:mfa/$aws_user_email --token-code $mfa --profile "$AWS_PROFILE" > $filename

# These lines only work with GNU Grep (MacOS uses BSD Grep by default).
# aws_access_key_id=$(grep -oP '(?<="AccessKeyId": ")[^"]*' $filename)
# aws_secret_access_key=$(grep -oP '(?<="SecretAccessKey": ")[^"]*' $filename)
# aws_session_token=$(grep -oP '(?<="SessionToken": ")[^"]*' $filename)

aws_access_key_id=$(grep -o '"AccessKeyId": "[^"]*' $filename | grep -o '[^"]*$')
aws_secret_access_key=$(grep -o '"SecretAccessKey": "[^"]*' $filename | grep -o '[^"]*$')
aws_session_token=$(grep -o '"SessionToken": "[^"]*' $filename | grep -o '[^"]*$')

echo "------------------"
echo "Exported variables:"
echo "------------------"
export AWS_ACCESS_KEY_ID=$aws_access_key_id
export AWS_SECRET_ACCESS_KEY=$aws_secret_access_key
export AWS_SESSION_TOKEN=$aws_session_token

print_masked_var

rm -rf $filename
