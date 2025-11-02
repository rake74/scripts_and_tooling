#
# Changes the current directory to a git repository based on a partial name.
#
# This function finds all git repositories within a root directory, selects the
# "best" match (shortest path), and changes into it. It can also navigate
# directly into a subdirectory within the matched repository.
#
# The must be sourced, then then repo function can change you CWD.
#
# Usage:
#   repo <repo_pattern>
#   repo <repo_pattern/sub/path>
#   repo [-v|--verbose] <repo_pattern[/sub/path]>
#
repo() {
  # The root directory where repositories are stored.
  local REPO_ROOT="${HOME}/repos"
  local verbose=false
  local user_input
  local search_pattern
  local sub_path

  # --- Argument Parsing ---
  if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
    verbose=true
    shift # Consume the flag to access the next argument.
  fi

  user_input="$1"

  if [ -z "${user_input}" ]; then
    echo "Usage: repo [-v|--verbose] <repo_pattern[/sub/path]>"
    return
  fi

  # --- Input Processing ---
  # Separate the repository search pattern from the optional sub-path.
  if [[ "${user_input}" == */* ]]; then
    search_pattern="${user_input%%/*}"
    sub_path="${user_input#*/}"
  else
    search_pattern="${user_input}"
    sub_path=""
  fi

  # --- Repository Discovery ---
  # Find only top-level .git directories. The -prune action prevents find
  # from descending into a directory once a .git is found, ignoring submodules.
  local repos
  repos=$(find "${REPO_ROOT}" -type d -name ".git" -prune | sed 's#/\.git##')

  if [ -z "${repos}" ]; then
    echo "No git repositories found in ${REPO_ROOT}"
    return 1
  fi

  # Filter the repository list based on the user's search pattern.
  local all_matches
  all_matches=$(echo "${repos}" | grep -i "${search_pattern}")

  if [ -z "${all_matches}" ]; then
    echo "No repository found matching '${search_pattern}'"
    return 1
  fi

  # --- Best Match Selection ---
  # Sort matches by string length (shortest first) to determine the best match.
  local sorted_matches
  sorted_matches=$(echo "${all_matches}" | awk '{ print length, $0 }' | sort -n | cut -d' ' -f2-)

  local best_match
  best_match=$(echo "${sorted_matches}" | head -n 1)

  local other_matches
  other_matches=$(echo "${sorted_matches}" | tail -n +2)

  # --- Output and User Feedback ---
  if [ -n "${other_matches}" ]; then
    if [ "$verbose" = true ]; then
      echo "Other possible matches:"
      echo "${other_matches}"
    else
      local other_count
      other_count=$(echo "${other_matches}" | grep -c .)

      echo "Other possible matches:"
      echo "${other_matches}" | head -n 3

      if [ "${other_count}" -gt 3 ]; then
        local remaining_count=$((other_count - 3))
        echo "... and ${remaining_count} more."
      fi
    fi
    echo ""
  fi

  # --- Final Navigation ---
  local final_dir="${best_match}"
  if [ -n "${sub_path}" ]; then
    # If a sub-path was provided, attempt to use it.
    if [ -d "${best_match}/${sub_path}" ]; then
      final_dir="${best_match}/${sub_path}"
    else
      # Otherwise, fall back to the repo root with a warning.
      >&2 echo "Warning: Directory '${sub_path}' not found. Using repo root."
    fi
  fi

  cd "${final_dir}"
  echo "Using: $(pwd)"
}
