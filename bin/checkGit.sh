#!/bin/bash

# Written with the help of ChatGPT

# ANSI color codes
DARK_CYAN='\033[0;36m'
BRIGHT_CYAN='\033[1;36m'
BRIGHT_RED='\033[1;31m'
BRIGHT_GREEN='\033[1;32m'
BRIGHT_YELLOW='\033[1;33m'
NC='\033[0m' # No Color


# Function to display help/documentation
show_help() {
    echo "This tool recursively scans a directory to find Git repositories that have issues."
    echo "An issue is defined as something that could lead to data loss if the repository were to be deleted."
    echo "This includes uncommitted changes, untracked files, and unpushed commits."
    echo "It outputs each found repository with up to four symbols indicating different types of issues."
    echo ""
    echo "Example Output:"
    echo -e "  ${BRIGHT_CYAN}↑${BRIGHT_RED}!${BRIGHT_YELLOW}~${BRIGHT_GREEN}*${NC} ${DARK_CYAN}/path/to/repo${NC}"
    echo ""
    echo "Usage: $0 [-a | -f | -p | -d | -v | -V | -h] <directory>"
    echo ""
    echo "Options:"
    echo "  -a       Show all repositories, including those without any issues."
    echo "  -f       Fetch the latest changes from the remote repository."
    echo "  -p       Pull the latest changes from the remote repository (fast-forward only)."
    echo "  -d       Perform a deep check for unpushed but locally referenced commits."
    echo "  -v       Output detailed information for issues indicated by '*', '~', and '!' symbols."
    echo "  -V       Output the git status and results of fetch/pull calls for each repository."
    echo "  -h       Display this help message and exit."
    echo ""
    echo "Symbols:"
    echo "  ↑        There are local commits on the current branch that have not been pushed."
    echo "  !        There are unpushed but locally referenced commits (detected with -d option)."
    echo "  ~        There are uncommitted changes in the working tree."
    echo "  *        There are untracked files that are not ignored."
    echo ""
    exit 0
}

# Function to get unpushed references (branches and tags)
get_unpushed_references() {
    local dir=$1
    local unpushed_references=""

    # Get unpushed commits in branches
    local unpushed_branch_commits=$(git -C "$dir" log --branches --not --remotes --format="%h %s")
    unpushed_references+=$unpushed_branch_commits

    # Get local tags
    local local_tags=$(git -C "$dir" tag)
    if [ -n "$local_tags" ]; then
        # Fetch the list of remote tags
        local remote_tags=$(git -C "$dir" ls-remote --tags origin | awk '{print $2}' | sed 's|refs/tags/||' | sort -u)

        # Compare local tags with remote tags
        for tag in $local_tags; do
            if [[ ! $remote_tags =~ $tag ]]; then
                unpushed_references+=$'\n'"$tag"
            fi
        done
    fi

    echo "$unpushed_references"
}


# Function to check for unpushed but locally referenced commits (deep check)
has_unpushed_referenced_commits() {
    local dir=$1
    local unpushed_references=$(get_unpushed_references "$dir")
    [ -n "$unpushed_references" ]
}

# Function to get repository status symbols with padding
get_repo_status_symbols() {
    local dir=$1
    local deep=$2
    local unpushed_refs=$3
    local symbols=("${BRIGHT_CYAN} ${NC}" "${BRIGHT_RED} ${NC}" "${BRIGHT_YELLOW} ${NC}" "${BRIGHT_GREEN} ${NC}") # Spaces as placeholders

    # Check for local commits not pushed on the current branch
    if git -C "$dir" rev-list --count @{upstream}..HEAD &>/dev/null; then
        local ahead=$(git -C "$dir" rev-list --count @{upstream}..HEAD)
        [ "$ahead" -gt 0 ] && symbols[0]="${BRIGHT_CYAN}↑${NC}"
    fi

    # Deep check for unpushed but locally referenced commits
    if [ "$deep" = true ] && [ -n "$unpushed_refs" ]; then
        symbols[1]="${BRIGHT_RED}!${NC}"
    fi

    # Check for uncommitted changes
    git -C "$dir" diff --quiet || symbols[2]="${BRIGHT_YELLOW}~${NC}"

    # Check for untracked files that are not ignored
    if git -C "$dir" status --porcelain | grep -q "^??"; then
        symbols[3]="${BRIGHT_GREEN}*${NC}"
    fi

    # Combine symbols into a single string
    echo -e "${symbols[0]}${symbols[1]}${symbols[2]}${symbols[3]}"
}

# Function to scan directories
scan_dir() {
    for dir in "$1"/*; do
        if [ -d "$dir" ] && [ -d "$dir/.git" ]; then
            local fetch_pull_output=""
            if [ "$fetch" = true ]; then
                fetch_pull_output=$(git -C "$dir" fetch 2>&1)
            fi
            if [ "$pull" = true ]; then
                fetch_pull_output+=$(git -C "$dir" pull --ff-only 2>&1)
            fi

            local unpushed_refs=""
            if [ "$deep_check" = true ]; then
                unpushed_refs=$(get_unpushed_references "$dir")
            fi

            local symbols=$(get_repo_status_symbols "$dir" "$deep_check" "$unpushed_refs")

            local show_repo=false
            if [[ "$show_all" = true || "$symbols" =~ [↑!~*] ]]; then
                show_repo=true
            fi

            if [ "$show_repo" = true ]; then
                echo -e "$symbols ${DARK_CYAN}$dir${NC}"

                if [ "$very_verbose" = true ] && [ -n "$fetch_pull_output" ]; then
                    echo "$fetch_pull_output"
                fi

                if [ "$verbose" = true ]; then
                    if [[ "$symbols" == *"*"* ]]; then
                        echo "Untracked files:"
                        git -C "$dir" --no-pager ls-files --others --exclude-standard
                    fi
                    if [[ "$symbols" == *"~"* ]]; then
                        echo "Uncommitted changes:"
                        git -C "$dir" --no-pager diff --name-only
                    fi
                    if [ -n "$unpushed_refs" ]; then
                        echo "Unpushed references:"
                        echo "$unpushed_refs"
                    fi
                    echo ""
                elif [ "$very_verbose" = true ]; then
                    local status_output=$(git -C "$dir" --no-pager status)
                    echo "$status_output"
                    echo ""
                fi
            fi
        elif [ -d "$dir" ]; then
            scan_dir "$dir"
        fi
    done
}


# Initialize options
show_all=false
fetch=false
pull=false
deep_check=false
verbose=false
very_verbose=false

# Check for options
while getopts ":afpdvVh" option; do
    case $option in
        a) show_all=true ;;
        f) fetch=true ;;
        p) pull=true ;;
        d) deep_check=true ;;
        v) verbose=true ;;
        V) very_verbose=true; verbose=true ;;
        h) show_help ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND-1))

# Check if an argument is provided
[ "$#" -ne 1 ] && show_help

# The directory to scan
SCAN_DIR=$1

# Start scanning
scan_dir "$SCAN_DIR"
