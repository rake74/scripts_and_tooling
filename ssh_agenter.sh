#!/bin/bash

# This script starts ssh-agent if not running, saves its environment variables,
# and dynamically loads all private keys that the ssh client would use.

# It is designed to be sourced in shell startup files like .bashrc or .bash_profile
# Example: source ~/bin/ssh_agenter.sh

ssh_agenter() {
  local sess_file
  local sess_sock
  local VERBOSE=${verbose:-false}
  local message=''
  local cleanup_unset=false

  sess_file=$(readlink -f ~/.ssh/ssh_agent)
  sess_sock=$(readlink -f ~/.ssh/ssh_agent_sock)

  # Unset to ensure we load from the session file or a new agent
  SSH_AUTH_SOCK=''
  SSH_AGENT_PID=''

  # If a session file exists, load the variables from it
  [ -f "$sess_file" ] && eval "$(cat "$sess_file")"

  ssh_agenter_verbose() { $VERBOSE && echo -e "$@" 1>&2 ; }

  ssh_agenter_funcs_cleanup() {
    unset -f ssh_agenter_add_ssh_keys
    unset -f ssh_agenter_agent_pid
    unset -f ssh_agenter_cleanup
    unset -f ssh_agenter_id_list
    unset -f ssh_agenter_verbose
    unset -f ssh_agenter_funcs_cleanup
  }

  # Clean up existing agent processes and files
  ssh_agenter_cleanup() {
    [ -n "${message}" ] && ssh_agenter_verbose "$@ - cleaning up processes and files"
    # Kill any ssh-agent processes running for the current user
    killall -s9 ssh-agent --user "$(id --user --name)" 2> /dev/null
    rm -f "$sess_sock" "$sess_file"
    SSH_AUTH_SOCK=''
    SSH_AGENT_PID=''
    $cleanup_unset && ssh_agenter_funcs_cleanup
  }

  ssh_agenter_id_list() { ssh-add -L 2> /dev/null ; }
  ssh_agenter_agent_pid() { ps -hp "$SSH_AGENT_PID" 2> /dev/null ; }

  # Determine if the existing agent is invalid, warranting a cleanup
  local cleanup_reason=()
  [ -z "$SSH_AUTH_SOCK" ] || [ -z "$SSH_AGENT_PID" ]   && cleanup_reason+=('SSH vars not set')
  [ -n "$SSH_AGENT_PID" ] && [ -z "$(ssh_agenter_agent_pid)" ] && cleanup_reason+=('agent not running')
  [ -n "$SSH_AUTH_SOCK" ] && [ ! -S "$SSH_AUTH_SOCK" ] && cleanup_reason+=('auth sock not right/missing')

  if (( ${#cleanup_reason[@]} > 0 )); then
    message="$(printf "%s, " "${cleanup_reason[@]}")" ssh_agenter_cleanup
  fi

  # Dynamically discover and add all configured SSH identity files
  ssh_agenter_add_ssh_keys() {
    local key_files_to_try
    # Use ssh -G to get the actual list of identity files ssh will use
    # mapfile reads each line of output into an array element
    mapfile -t key_files_to_try < <(
      ssh -G localhost | sed -n '/^identityfile/I!d;s/^identityfile\s\+//I; '"; s|~|$HOME| p"
    )

    if (( ${#key_files_to_try[@]} == 0 )); then
      ssh_agenter_verbose "Could not determine any identity files from 'ssh -G localhost'."
      return
    fi

    local key_file
    for key_file in "${key_files_to_try[@]}"; do
      # Continue to the next key if this one doesn't exist
      [ ! -f "$key_file" ] && continue

      # Check if the public key is already in the agent to avoid duplicates
      if [ -f "${key_file}.pub" ] && ssh_agenter_id_list | grep -q -F "$(awk '{print $2}' "${key_file}.pub")"; then
        ssh_agenter_verbose "Key ${key_file} already in agent."
      else
        # Add the key, suppressing output on failure unless in ssh_agenter_verbose mode
        ssh-add "$key_file" &>/dev/null || ssh_agenter_verbose "Could not add ${key_file}. Requires passphrase or is invalid."
      fi
    done
  }

  # If no agent socket is set, it's time to start a new agent
  if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -a "$sess_sock")" || {
      echo 'Something went wrong with ssh-agent' 1>&2
      unset_cleanup=true ssh_agenter_cleanup
      return 1
    }

    ssh_agenter_add_ssh_keys

    # If, after trying, no keys were loaded, clean up the new agent
    if [ -z "$(ssh_agenter_id_list)" ]; then
      message='No usable identities found; shutting down new agent.' unset_cleanup=true ssh_agenter_cleanup
      return 1
    fi

    # Save the new agent's variables to the session file for other shells
    {
      echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK ; export SSH_AUTH_SOCK"
      echo "SSH_AGENT_PID=$SSH_AGENT_PID ; export SSH_AGENT_PID"
    } > "$sess_file"
    chmod 600 "$sess_file" # Use secure permissions for the session file
  else
    # If an agent is already running, just ensure all configured keys are loaded
    ssh_agenter_add_ssh_keys
  fi

  # Final check: if no identities are loaded at all, there's no point
  if [ -z "$(ssh_agenter_id_list)" ]; then
    message='No identities loaded in agent.' unset_cleanup=true ssh_agenter_cleanup
    return 1
  fi

  ssh_agenter_funcs_cleanup

  # Export the variables for the current shell to use
  #echo "SSH_AGENT_PID=$SSH_AGENT_PID"
  #echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
  #echo "export SSH_AGENT_PID"
  #echo "export SSH_AUTH_SOCK"
}

ssh_agenter
