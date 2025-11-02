#
# Changes the current directory to a git repository based on a partial name.
#
# This function finds git repositories, allowing specific repos or entire
# directories to be ignored via a semaphore file named '.repoignore'.
# It selects the "best" match and can navigate into a sub-path.
#
# --- Best Match Logic ---
# 1. Prioritizes repositories where the name STARTS WITH the search term.
# 2. Falls back to repositories where the name CONTAINS the search term.
# 3. Within each group, the shortest full path is preferred.
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
    while [[ "$1" == -* ]]; do
        case "$1" in
            --all) list_all=true; shift ;;
            -v|--verbose) verbose=true; shift ;;
            *) break ;;
        esac
    done

    user_input="$1"

    if [ "$list_all" = false ] && [ -z "${user_input}" ]; then
        echo "Usage: repo [--all [pattern]] [-v|--verbose] <repo_pattern[/sub/path]>"
        return 1
    fi

    # --- Optimized Repository Discovery (Single Pass) ---
    local discovered_paths
    discovered_paths=$(find "${REPO_ROOT}" -name ".git" -o -name ".repoignore" 2>/dev/null)

    local ignored_parents=$(echo "${discovered_paths}" | grep '/\.repoignore$' | grep -v '/\.git/' | sed 's#/\.repoignore##')
    local ignored_singles=$(echo "${discovered_paths}" | grep '/\.git/\.repoignore$' | sed 's#/\.git/\.repoignore##')
    local all_repos=$(echo "${discovered_paths}" | grep '/\.git$' | sed 's#/\.git##')

    local repos
    if [ -n "${ignored_parents}" ] || [ -n "${ignored_singles}" ]; then
        repos=$(echo "${all_repos}" | grep -vFf <(echo -e "${ignored_parents}\n${ignored_singles}" | sed '/^$/d'))
    else
        repos="${all_repos}"
    fi

    # --- Handle --all (List-Only Mode) ---
    if [ "$list_all" = true ]; then
        local output="${repos}"
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

    local all_matches=$(echo "${repos}" | grep -i "${search_pattern}")

    if [ -z "${all_matches}" ]; then
        echo "No repository found matching '${search_pattern}'"
        return 1
    fi

    # --- Best Match Selection (with Scoring) ---
    local sorted_matches
    sorted_matches=$(echo "${all_matches}" | \
        awk -v term="${search_pattern}" '
        {
            n = split($0, parts, "/");
            basename = parts[n];
            low_basename = tolower(basename);
            low_term = tolower(term);

            score = 2; # Default score for a "contains" match
            if (index(low_basename, low_term) == 1) {
                score = 1; # Better score for a "starts with" match
            }
            print score, length($0), $0;
        }' | \
        sort -n -k1,1 -k2,2 | \
        cut -d' ' -f3-)

    local best_match=$(echo "${sorted_matches}" | head -n 1)
    local other_matches=$(echo "${sorted_matches}" | tail -n +2)

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

    echo Using:
    echo "${final_dir}"
    cd "${final_dir}"
}
