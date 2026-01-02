#!/usr/bin/env zsh
# aws-ssh.plugin.zsh

# Check for AWS credentials
_aws_check_credentials() {
  local profile=$1
  local profile_args=()

  if [[ -n "$profile" ]]; then
    profile_args=(--profile "$profile")
  fi

  if ! aws "${profile_args[@]}" sts get-caller-identity >/dev/null 2>&1; then
    if [[ -n "$profile" ]]; then
      echo "AWSSSH:INFO: AWS credentials for profile $profile not found. Please run 'aws configure --profile $profile'."
    else
      echo "AWSSSH:INFO: AWS credentials not found. Please set AWS_PROFILE or run 'aws configure'."
    fi
    return 1
  fi
}

_aws_print_help() {
  cat <<'EOF'
Usage: awsssh [options]

Options:
  --region=REGION           AWS region for queries and sessions. Required if no default region is configured.
  --profile=PROFILE         AWS CLI profile to use.
  --connection=TYPE         Connection method: ssh or ssm (default: ssm).
  --instance=NAME           Skip fzf; connect to the first instance matching this Name tag or instance ID.
  --forward=SPEC            Port forward spec local:host:remote. Repeat flag for multiple forwards.
  --help, -h                Show this help message and exit.

Examples:
  awsssh --profile prod --region eu-central-1
  awsssh --connection=ssm --forward=8080:localhost:80 --forward=3306:db.internal:3306
EOF
}

_aws_require_fzf() {
  if ! command -v fzf >/dev/null 2>&1; then
    echo "AWSSSH:ERROR: fzf binary not found in PATH. Install fzf to continue."
    return 1
  fi
}

# Query AWS EC2 instances
_aws_query_for_instances() {
  local region=$1
  local profile=$2
  local filter=$3
  local include_header=${4:-1}
  local aws_cmd=(aws)

  [[ -n "$profile" ]] && aws_cmd+=(--profile "$profile")
  [[ -n "$region" ]] && aws_cmd+=(--region "$region")
  aws_cmd+=(ec2 describe-instances --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value | [0], InstanceId, PrivateIpAddress, PublicIpAddress, State.Name, ImageId, InstanceType, PublicDnsName]' --output text)

  if [[ -n "$filter" ]]; then
    if [[ "$filter" == i-* ]]; then
      aws_cmd+=(--instance-ids "$filter")
    else
      aws_cmd+=(--filters "Name=tag:Name,Values=$filter")
    fi
  fi

  if [[ "$include_header" -eq 1 ]]; then
    printf "%-30s\t%-20s\t%-15s\t%-15s\t%-15s\t%-20s\t%-10s\t%s\n" "Name" "Instance ID" "Private IP" "Public IP" "Status" "AMI" "Type" "Public DNS Name"
  fi

  "${aws_cmd[@]}" |
    grep -vE '^None$' |
    # Ensure awk prints fields in the correct order
    awk '{printf "%-30s\t%-20s\t%-15s\t%-15s\t%-15s\t%-20s\t%-10s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8}'
}

# Handle SSH connection
_aws_ssh_command() {
  local selection=$1 connection=$2 region=$3 profile=$4 forwards_str=$5
  local name=$(echo $selection | awk '{print $1}')
  local public_dns=$(echo $selection | awk '{print $8}')
  local instance_id=$(echo $selection | awk '{print $2}')
  local instance_status=$(echo $selection | awk '{print $5}')
  local ssh_user="ec2-user"
  local -a forwards

  if [[ -n "$forwards_str" ]]; then
    IFS=',' read -rA forwards <<< "$forwards_str"
  fi

  if [[ "$instance_status" != "running" ]]; then
    echo "AWSSSH:INFO: Instance $name ($instance_status) is not running."
    return 1
  fi

  if [[ "$connection" == "ssh" && -n "$public_dns" ]]; then
    echo "AWSSSH:INFO: Connecting to $name ($public_dns) as $ssh_user..."
    local ssh_cmd=(ssh)

    for forward in "${forwards[@]}"; do
      local spec=${forward//[[:space:]]/}
      [[ -z $spec ]] && continue
      ssh_cmd+=(-L "$spec")
    done

    ssh_cmd+=("$ssh_user@$public_dns")
    "${ssh_cmd[@]}"
  elif [[ "$connection" == "ssm" && -n "$instance_id" ]]; then
    if [[ ${#forwards[@]} -eq 0 ]]; then
      echo "AWSSSH:INFO: Connecting to $name ($instance_id) with AWS SSM session..."
      local aws_cmd=(aws)
      [[ -n "$profile" ]] && aws_cmd+=(--profile "$profile")
      [[ -n "$region" ]] && aws_cmd+=(--region "$region")
      aws_cmd+=(ssm start-session --target "$instance_id")
      "${aws_cmd[@]}"
    else
      if [[ ${#forwards[@]} -gt 1 ]]; then
        echo "AWSSSH:INFO: Multiple forwards detected; starting sessions sequentially."
      fi

      for forward in "${forwards[@]}"; do
        local spec=${forward//[[:space:]]/}
        [[ -z $spec ]] && continue
        local local_port host_port remote_port host
        local_port=${spec%%:*}
        host_port=${spec#*:}

        if [[ "$host_port" == "$spec" ]]; then
          echo "AWSSSH:ERROR: Invalid forward specification '$spec'. Expected format local:host:remote."
          continue
        fi

        host=${host_port%%:*}
        remote_port=${host_port##*:}

        if [[ -z "$host" || "$host" == "$host_port" || -z "$remote_port" ]]; then
          echo "AWSSSH:ERROR: Invalid forward specification '$spec'. Expected format local:host:remote."
          continue
        fi

        echo "AWSSSH:INFO: Starting port forward on $name ($instance_id) $local_port->$host:$remote_port via SSM..."
        local aws_cmd=(aws)
        [[ -n "$profile" ]] && aws_cmd+=(--profile "$profile")
        [[ -n "$region" ]] && aws_cmd+=(--region "$region")
        aws_cmd+=(ssm start-session --target "$instance_id" --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters "{\"portNumber\":[\"$remote_port\"],\"localPortNumber\":[\"$local_port\"],\"host\":[\"$host\"]}")
        "${aws_cmd[@]}"
      done
    fi
  else
    echo "AWSSSH:INFO: Unable to connect to $name ($instance_id) with $connection."
  fi
}

# Launch connections directly as windows in the asw_ssh session
_launch_connections() {
  local selections="$1"
  local connection="$2"
  local region="$3"
  local profile="$4"
  local forwards_str="$5"

  local selection_count=$(echo "$selections" | wc -l)

  if [[ $selection_count -gt 1 ]]; then
    tmux has-session -t "asw_ssh" 2>/dev/null || tmux new-session -d -s "asw_ssh"

    while IFS= read -r selection; do
      local name=$(echo $selection | awk '{print $1}')
      local instance_id=$(echo $selection | awk '{print $2}')
      local window_name="ssh:${name}:${instance_id}"

      if ! tmux list-windows -t "asw_ssh" | grep -q "$window_name"; then
        tmux new-window -d -n "$window_name" -t "asw_ssh" \
          "zsh -c 'source $HOME/.zshrc; _aws_ssh_command \"$selection\" \"$connection\" \"$region\" \"$profile\" \"$forwards_str\"; zsh'"
      else
        echo "AWSSSH:ERROR: Window $window_name already exists."
      fi
    done <<<"$selections"

    tmux attach-session -t "asw_ssh"
  else
    local selection=$(echo "$selections" | head -n 1)
    _aws_ssh_command "$selection" "$connection" "$region" "$profile" "$forwards_str"
  fi
}

# Main function
_aws_ssh_main() {
  local region=${AWS_REGION:-$(aws configure get region)}
  local connection="ssm"
  local profile=${AWS_PROFILE:-}
  local -a forwards
  local instance_filter=""

  while [[ $# -gt 0 ]]; do
    case $1 in
    --help|-h)
      _aws_print_help
      return 0
      ;;
    --region=*)
      region="${1#*=}"
      ;;
    --connection=*)
      connection="${1#*=}"
      ;;
    --profile=*)
      profile="${1#*=}"
      ;;
    --forward=*)
      forwards+=("${1#*=}")
      ;;
    --instance=*)
      instance_filter="${1#*=}"
      ;;
    *)
      echo "AWSSSH:ERROR: Unknown option: $1"
      return 1
      ;;
    esac
    shift
  done

  if [[ -z "$region" ]]; then
    echo "AWSSSH:ERROR: AWS region not specified. Use --region or configure a default."
    return 1
  fi

  _aws_check_credentials "$profile" || return 1
  local forwards_str="${(j:,:)forwards}"
  if [[ -n "$instance_filter" ]]; then
    local matches=$(_aws_query_for_instances "$region" "$profile" "$instance_filter" 0)
    if [[ -z "$matches" ]]; then
      echo "AWSSSH:ERROR: No instance matched '$instance_filter' in region $region."
      return 1
    fi

    local match_count=$(echo "$matches" | wc -l | tr -d '[:space:]')
    if [[ $match_count -gt 1 ]]; then
      echo "AWSSSH:INFO: Multiple instances matched '$instance_filter'; using the first result."
    fi

    local selection=$(echo "$matches" | head -n 1)
    _aws_ssh_command "$selection" "$connection" "$region" "$profile" "$forwards_str"
    return $?
  fi

  _aws_require_fzf || return 1

  local selections=$(
    _aws_query_for_instances "$region" "$profile" |
      fzf \
        --height=40% \
        --layout=reverse \
        --border \
        --border-label="EC2 Instances" \
        --info=default \
        --multi \
        --prompt="Search Instance: " \
        --header="Select (Enter), Toggle Details (Ctrl-/), Quit (Ctrl-C or ESC)" \
        --header-lines=1 \
        --bind="ctrl-/:toggle-preview" \
        --preview-window="right:40%:wrap" \
        --preview-label="Details" \
        --preview='
        echo {} |
        awk -F"\t" "{
          print \"Name: \" \$1 \"\\nInstance ID: \" \$2 \"\\nPrivate IP: \" \$3 \"\\nPublic IP: \" \$4 \"\\nStatus: \" \$5 \"\\nAMI: \" \$6 \"\\nType: \" \$7 \"\\nPublic DNS Name: \" \$8
        }"
        ' \
        --delimiter=$'\t' \
        --with-nth=1,2,3,4,5
  )

  if [[ -z "$selections" ]]; then
    echo "AWSSSH:INFO: No instances selected. Exiting..."
    return 1
  fi

  _launch_connections "$selections" "$connection" "$region" "$profile" "$forwards_str"
}

alias awsssh='_aws_ssh_main'