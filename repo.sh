#
# Changes the current directory to a git repository based on a partial name.
#
# This function finds git repositories, allowing specific repos or entire
# directories to be ignored via a semaphore file named '.repoignore'.
# It selects the "best" match (shortest path) and can navigate into a sub-path.
#
# --- Ignoring Repositories ---
# 1. To ignore a SINGLE repository:
#    $ touch path/to/my-repo/.git/.repoignore
#
# 2. To ignore an ENTIRE directory of repositories:
#    $ touch path/to/archive/.repoignore
#
# --- Usage ---
#   repo <pattern>                  # Find and cd to best match for <pattern>
#   repo <pattern/sub/path>         # cd into a sub-path of the best match
#   repo --all                      # List all visible (non-ignored) repos
#   repo --all <pattern>            # List visible repos filtered by <pattern>
#   repo [-v|--verbose] <pattern>   # Verbose mode for multiple matches
#
repo() {
    local REPO_ROOT="${HOME}/repos"
    local verbose=false
    local list_all=false
    local user_input
    local search_pattern
    local sub_path

    # --- Argument Parsing ---
    # This loop allows flags to be processed correctly regardless of order.
    while [[ "$1" == -* ]]; do
        case "$1" in
            --all)
                list_all=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            *)
                # Stop parsing if an unknown option or -- is encountered
                break
                ;;
        esac
    done

    user_input="$1"

    # Validate that if we are not in list_all mode, a pattern is required.
    if [ "$list_all" = false ] && [ -z "${user_input}" ]; then
        echo "Usage: repo [--all [pattern]] [-v|--verbose] <repo_pattern[/sub/path]>"
        return 1
    fi

    # --- Optimized Repository Discovery (Single Pass) ---
    # Find all relevant markers (.git dirs and .repoignore files) in one go.
    local discovered_paths
    discovered_paths=$(find "${REPO_ROOT}" -name ".git" -o -name ".repoignore" 2>/dev/null)

    # Step 1: From the results, build a list of paths that should be ignored.
    local ignored_parents
    ignored_parents=$(echo "${discovered_paths}" | grep '/\.repoignore$' | grep -v '/\.git/' | sed 's#/\.repoignore##')
    local ignored_singles
    ignored_singles=$(echo "${discovered_paths}" | grep '/\.git/\.repoignore$' | sed 's#/\.git/\.repoignore##')

    # Step 2: From the results, build a list of all possible repo paths.
    local all_repos
    all_repos=$(echo "${discovered_paths}" | grep '/\.git$' | sed 's#/\.git##')

    # Step 3: Filter out any repo that is inside an ignored path.
    local repos
    if [ -n "${ignored_parents}" ] || [ -n "${ignored_singles}" ]; then
        repos=$(echo "${all_repos}" | grep -vFf <(echo -e "${ignored_parents}\n${ignored_singles}" | sed '/^$/d'))
    else
        repos="${all_repos}"
    fi

    # --- Handle --all (List-Only Mode) ---
    if [ "$list_all" = true ]; then
        local output="${repos}"
        # If a search pattern was also provided, filter the results.
        if [ -n "${user_input}" ]; then
            output=$(echo "${repos}" | grep -i "${user_input}")
        fi

        if [ -n "${output}" ]; then
            echo "${output}"
        else
            echo "No visible repositories found."
        fi
        return 0
    fi

    # --- The rest of the script only runs if --all was NOT specified ---

    # --- Input Processing ---
    if [[ "${user_input}" == */* ]]; then
        search_pattern="${user_input%%/*}"
        sub_path="${user_input#*/}"
    else
        search_pattern="${user_input}"
        sub_path=""
    fi

    if [ -z "${repos}" ]; then
        echo "No git repositories found in ${REPO_ROOT}"
        return 1
    fi

    local all_matches
    all_matches=$(echo "${repos}" | grep -i "${search_pattern}")

    if [ -z "${all_matches}" ]; then
        echo "No repository found matching '${search_pattern}'"
        return 1
    fi

    # --- Best Match Selection ---
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
            local other_count=$(echo "${other_matches}" | grep -c .)
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
        if [ -d "${best_match}/${sub_path}" ]; then
            final_dir="${best_match}/${sub_path}"
        else
            >&2 echo "Warning: Directory '${sub_path}' not found. Using repo root."
        fi
    fi

    cd "${final_dir}"
    echo "Using: $(pwd)"
}
