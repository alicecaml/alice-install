#!/bin/sh
set -eu

# The whole body of the script is wrapped in a function so that a partially
# downloaded script does not get executed by accident. The function is called
# at the end.
main () {
    alice_git_url="https://github.com/alicecaml/alice"

    # Reset
    Color_Off='\033[0m' # Text Reset

    # Regular Colors
    Red='\033[0;31m'    # Red
    Green='\033[0;32m'  # Green
    Yellow='\033[0;33m' # Yellow
    White='\033[0;0m'   # White

    # Bold
    Bold_Green='\033[1;32m' # Bold Green
    Bold_White='\033[1m'    # Bold White

    print_error() {
        printf "%berror%b: %s\n" "$Red" "$Color_Off" "$*" >&2
    }

    error() {
        print_error "$@"
        exit 1
    }

    error_download_failed() {
        tar_uri="$1"
        version="$2"
        print_error "Failed to download Alice archive from \"$tar_uri\""
        print_error "Check that $version corresponds to a version of Alice with a binary release."
        print_error "A list of Alice versions with binary releases can be found at: $alice_git_url/releases"
        exit 1
    }

    warn() {
        printf "%bwarn%b: %s\n" "$Yellow" "$Color_Off" "$*" >&2
    }

    info() {
         printf "%b%s %b" "$White" "$*" "$Color_Off"
    }

    code() {
        printf "%s\n" "$1"
    }

    info_bold() {
        printf "%b%s %b" "$Bold_White" "$*" "$Color_Off"
    }

    success() {
        printf "%b%s %b" "$Green" "$*" "$Color_Off"
    }

    success_bold() {
        printf "%b%s %b" "$Bold_Green" "$*" "$Color_Off"
    }

    command_exists() {
        command -v "$1" >/dev/null 2>&1
    }

    ensure_command() {
        command_exists "$1" || error "Failed to find \"$1\". This script needs \"$1\" to be able to install Alice."
    }

    unsubst_home() {
        echo "$1" | sed -e "s#^$HOME#\$HOME#"
    }

    latest_stable_binary_alice_version() {
        ensure_command "git"
        git_url="$1"
        # matches stable version numbers like "1.2.3"
        stable_version_filter='^[0-9]\+\.[0-9]\+\.[0-9]\+$'
        git ls-remote --tags "$git_url" | cut -f2 | sed 's#^refs/tags/##' | grep "$stable_version_filter" | sort -V | tail -n1
    }

    get_parent_pid_of_pid() {
        # Get the PID of the parent of a given process, specified by PID.
        pid="$1"
        # Use awk to select the appropriate line of output rather than ps's own
        # filtering as the latter is not always available (e.g. in busybox's ps
        # implementation - the default for alpine linux).
        ps -o pid=,ppid= | awk "\$1==$pid {print \$2}"
    }

    get_command_of_pid() {
        # Get the command of the parent of a given process, specified by PID.
        pid="$1"
        # Take the first word of its command. Sometimes the command is prefixed
        # with a "-" indicating a login shell, so strip any leading "-"
        # character. Use awk to select the appropriate line of output rather
        # than ps's own filtering as the latter is not always available (e.g.
        # in busybox's ps implementation - the default for alpine linux).
        ps -o pid=,comm= | awk "\$1==$pid {print \$2}" | sed 's/^-//'
    }

    infer_shell_name() {
        if [ -n "${SHELL+x}" ]; then
            # The SHELL variable is often a variable within the current shell
            # session but is rarely exported as an environment variable.
            # Consequently it won't be inherited by the /bin/sh process running
            # this script, and thus will be unset. If SHELL is set here, this
            # means the user chose to export it as an environment variable,
            # e.g. by choosing to add `export SHELL` to their shell config file
            # or with a line like `ENV SHELL=/bin/bash` in a Dockerfile. We'll
            # interpret the presence of a SHELL environment variable to mean
            # that the user wants to treat its value as their shell.
            basename "$SHELL"
        else
            # This is the common case. If this script was started by piping a
            # command to /bin/sh or otherwise running the script from the
            # command-line then its parent process will be the user's shell.
            # This is a more reliable way to determine the user's shell than
            # the contents of this process's environment since the variables
            # that might indicate the user's shell are rarely exported as
            # environment variables (ie. they are shell variables instead).

            # Get the PID of the parent of this process.
            parent_pid=$(get_parent_pid_of_pid $$)
            if [ -n "$parent_pid" ] && [ "$parent_pid" != "0" ]; then
                # Get the command of the parent process to find out the user's shell.
                parent_command=$(basename "$(get_command_of_pid "$parent_pid")")
                case "$parent_command" in
                    expect)
                        # If the parent command was "expect" we can infer that
                        # the script is being run interactively by the "expect"
                        # program. This happens in some tests of the
                        # interactive elements of this script, and it's also
                        # possible that a user may also run the script via
                        # "expect" in production (though hopefully not!)
                        # instead of passing arguments on the command-line.
                        # When this happens, the user's shell is probably the
                        # parent of the expect process (ie. the grandparent of
                        # the current process).
                        grandparent_pid=$(get_parent_pid_of_pid "$parent_pid")
                        if [ -n "$grandparent_pid" ] && [ "$grandparent_pid" != "0" ]; then
                            grandparent_command=$(basename "$(get_command_of_pid "$grandparent_pid")")
                            if [ "$grandparent_command" != "expect" ]; then
                                echo "$grandparent_command"
                                return
                            fi
                        fi
                        ;;
                    *)
                        echo "$parent_command"
                        return
                        ;;
                esac
            fi
            warn "Unable to identify your shell. Assuming posix sh. Rerun the installer with the '--shell' option to override."
            echo "sh"
        fi
    }

    read_checked() {
        # Reads from either the terminal device or stdin depending on its
        # argument. Reading directly from the terminal is necessary when the
        # script is piped to /bin/sh, such as when installing by running the
        # `curl ... | sh` command. But when reading from the terminal it's not
        # possible use io redirection to populate the interactive fields, which
        # is sometimes helpful to do when testing.
        tty="$1"
        if [ "$tty" = "1" ]; then
            read -r input < /dev/tty
        else
            read -r input
        fi
        echo "$input"
    }

    y_or_n() {
        message="$1"
        while true; do
            info_bold "$message ([y]/n) >"
            choice=$(read_checked "$tty")
            case "$choice" in
                "")
                    return 0
                    ;;
                y|Y)
                    return 0
                    ;;
                n|N)
                    return 1
                    ;;
                *)
                    warn "Please enter y or n."
                    echo
                    ;;
            esac
        done
    }

    exit_message() {
        info_bold "This installer will now exit."
    }

    usage() {
        echo "Usage: install.sh [VERSION] [options]"
        echo
        echo "Install a given version of Alice, or the latest stable version if VERSION is not specified."
        echo "Existing versions are listed at: $alice_git_url/releases"
        echo "To install an unstable version (such as an alpha version) the version number must be specified explicitly."
        echo
        echo "Options:"
        echo "--help, -h                Print this help message"
        echo "--global PATH             Install Alice and development tools to PATH instead of installing under ~/.alice"
        echo "--no-prompt               Don't prompt before installing"
        echo "--install-tools           Install OCaml development tools"
        echo "--no-install-tools        Don't install OCaml development tools"
        echo "--install-compiler-only   When installing OCaml development tools, only install the compiler"
        echo "--update-shell-config     Always update the shell config (e.g. .bashrc) if necessary"
        echo "--no-update-shell-config  Never update the shell config (e.g. .bashrc)"
        echo "--shell-config PATH       Use this file as your shell config when updating the shell config"
        echo "--shell SHELL             One of: bash, zsh, fish, sh. Installer will treat this as your shell. Use 'sh' for minimal posix shells such as ash"
        echo "--just-print-version      Make no changes to the system. The final line of stdout will be the version of Alice that would have been installed"
        echo "--no-tty                  Read interactive input from stdin rather than the terminal device (allows automation via yes et al.)"
        echo "--debug-override-url URL  Download Alice tarball from given url (debugging only)"
        echo "--debug-tarball-dir DIR   Name of root directory inside tarball (debugging only)"
        echo "--debug-version-repo REPO Override the git repo url used to determine the latest version of Alice (debugging only)"
    }

    should_update_shell_config=""
    just_print_version="0"
    tty="1"
    prompt="y"
    install_tools=""
    install_compiler_only="n"
    while [ "$#" -gt "0" ]; do
        arg="$1"
        shift
        case "$arg" in
            -h|--help)
                usage
                exit 0
                ;;
            --global)
                if [ "$#" -eq "0" ]; then
                    error "--global must be passed an argument"
                fi
                global="$1"
                shift
                ;;
            --no-prompt)
                prompt="n"
                ;;
            --install-tools)
                install_tools="y"
                ;;
            --no-install-tools)
                install_tools="n"
                ;;
            --install-compiler-only)
                install_compiler_only="y"
                ;;
            --update-shell-config)
                should_update_shell_config="y"
                ;;
            --no-update-shell-config)
                should_update_shell_config="n"
                ;;
            --shell-config)
                if [ "$#" -eq "0" ]; then
                    error "--shell-config must be passed an argument"
                fi
                shell_config="$1"
                shift
                ;;
            --shell)
                if [ "$#" -eq "0" ]; then
                    error "--shell must be passed an argument"
                fi
                shell_name="$1"
                shift
                case "$shell_name" in
                    bash|zsh|fish|sh)
                        ;;
                    *)
                        error "--shell must be passed one of bash, zsh, fish, sh. Got $shell_name."
                        ;;
                esac
                ;;
            --just-print-version)
                just_print_version="1"
                ;;
            --no-tty)
                tty="0"
                ;;
            --debug-override-url)
                if [ "$#" -eq "0" ]; then
                    error "--debug-override-url must be passed an argument"
                fi
                debug_override_url="$1"
                shift
                ;;
            --debug-tarball-dir)
                if [ "$#" -eq "0" ]; then
                    error "--debug-tarball-dir must be passed an argument"
                fi
                debug_tarball_dir="$1"
                shift
                ;;
            --debug-version-repo)
                if [ "$#" -eq "0" ]; then
                    error "--debug-version-repo must be passed an argument"
                fi
                debug_version_repo="$1"
                shift
                ;;
            -*)
                print_error "Unknown option: $arg"
                usage
                exit 1
                ;;
            *)
                if [ -z "${version+x}" ]; then
                    version="$arg"
                else
                    error "Expected single anonymous argument (the Alice version) but got multiple: $version, $arg"
                fi
                ;;
        esac
    done

    echo
    info_bold "Welcome to the Alice installer!"
    echo

    if [ -z "${version+x}" ]; then
        echo
        info "No Alice version was specified, so the installer will check the latest stable version with a binary release..."
        echo
        version=$(latest_stable_binary_alice_version "${debug_version_repo:-"$alice_git_url"}")
        echo
        info "The latest release of Alice was found to be $version."
        echo
    fi

    if [ "$just_print_version" = "1" ]; then
        echo
        info "Exiting due to --just-print-version. Would install Alice version:"
        echo
        echo "$version"
        exit
    fi

    case $(uname -ms) in
        'Darwin x86_64')
            target=x86_64-macos
            ;;
        'Darwin arm64')
            target=aarch64-macos
            ;;
        'Linux x86_64')
            target=x86_64-linux-musl-static
            ;;
        *)
            error "The Alice installation script does not currently support $(uname -ms)."
    esac
    tarball="alice-$version-$target.tar.gz"
    tar_uri=${debug_override_url:-"$alice_git_url/releases/download/$version/$tarball"}
    # The tarball is expected to contain a single directory with this name:
    tarball_dir=${debug_tarball_dir:-"alice-$version-$target"}

    ensure_command "tar"
    ensure_command "gzip"
    ensure_command "curl"

    echo
    printf "This will guide you through the installation of %bAlice v%s%b."  "$Bold_White" "$version" "$Color_Off"
    echo

    if [ -z "${global+x}" ]; then
        install_root="$HOME/.alice/alice"
    else
        install_root="$global"
    fi

    echo
    if [ "$prompt" = "y" ] && ! y_or_n "Alice v$version will now be installed to '$install_root'. Proceed?"; then
        exit_message
        exit 0
    fi
    echo

    tmp_dir="$(mktemp -d -t alice-install.XXXXXXXX)"
    trap 'rm -rf "$tmp_dir"' EXIT

    # Determine whether we can use --no-same-owner to force tar to extract with user permissions.
    touch "$tmp_dir/tar-detect"
    tar cf "$tmp_dir/tar-detect.tar" -C "$tmp_dir" tar-detect
    if tar -C "$tmp_dir" -xf "$tmp_dir/tar-detect.tar" --no-same-owner; then
        tar_owner="--no-same-owner"
    else
        tar_owner=""
    fi
    tmp_tar="$tmp_dir/$tarball"

    if [ -z "${debug_override_url+x}" ]; then
        curl_proto="=https"
    else
        # When using a debugging url the tarball might not be served with https.
        curl_proto="all"
    fi
    curl --fail --location --progress-bar \
        --proto "$curl_proto" --tlsv1.2 \
        --output "$tmp_tar" --ipv4 "$tar_uri" ||
        error_download_failed "$tar_uri" "$version"

    tar -xf "$tmp_tar" -C "$tmp_dir" "$tar_owner" > /dev/null 2>&1 ||
        error "Failed to extract archive content from \"$tmp_tar\""

    mkdir -p "$install_root"
    for d in "$tmp_dir/$tarball_dir"/*; do
        cp -rf "$d" "$install_root"
    done

    # Run alice itself to install some extra scripts.
    "$install_root/bin/alice" internal setup

    echo
    success "Alice successfully installed to $install_root!"
    echo
    echo


    if ! [ "$should_update_shell_config" = "n" ]; then

        shell_name=${shell_name:-$(infer_shell_name)}
        env_dir="$HOME/.alice/env"
        case "$shell_name" in
            sh|ash|dash)
                shell_config_inferred="${shell_config:-$HOME/.profile}"
                env_file="$env_dir/env.sh"
                ;;
            bash)
                shell_config_inferred="${shell_config:-$HOME/.profile}"
                env_file="$env_dir/env.bash"
                ;;
            zsh)
                env_file="$env_dir/env.zsh"
                shell_config_inferred="$HOME/.zshrc"
                ;;
            fish)
                env_file="$env_dir/env.fish"
                shell_config_inferred="$HOME/.config/fish/config.fish"
                ;;
            *)
                info "The install script does not recognize your shell ($shell_name)."
                echo
                info "It's up to you to ensure $install_root/bin is in your \$PATH variable."
                echo
                exit_message
                echo
                exit 0
                ;;
        esac

        if [ -z "${shell_config+x}" ]; then
            info "The installer can modify your shell config file to set up your environment for running 'alice' from your terminal."
            echo
            info "The installer has inferred that your shell is: $shell_name. If this is incorrect, rerun the installer with --shell."
            echo
            info "Based on your shell ($shell_name) the installer has inferred that your shell config file is: $shell_config_inferred"
            echo
            while [ -z "${shell_config+x}" ]; do
                echo
                info "Enter the absolute path of your shell config file or leave blank for default (no modification will be performed yet):"
                echo
                info_bold "[$shell_config_inferred] >"
                choice=$(read_checked "$tty")
                case "$choice" in
                    "")
                        shell_config=$shell_config_inferred
                        ;;
                    '~'/*)
                        shell_config=$(echo "$choice" | sed "s#~#$HOME#")
                        echo
                        warn "Expanding $choice to $shell_config"
                        ;;
                    /*)
                        shell_config=$choice
                        ;;
                    *)
                        echo
                        warn "Not an absolute path: $choice"
                        ;;
                esac
            done
            echo
        fi

        shell_config_code() {
            case "$shell_name" in
                fish)
                    if_installed="if [ -f \"$(unsubst_home "$env_file")\" ]"
                    end_if="end"
                    ;;
                *)
                    if_installed="if [ -f \"$(unsubst_home "$env_file")\" ]; then"
                    end_if="fi"
                    ;;
            esac

            code ""
            code "# BEGIN configuration from Alice installer"
            code "$if_installed"
            # Use `.` rather than `source` because the former is more portable.
            code "    . \"$(unsubst_home "$env_file")\""
            code "$end_if"
            code "# END configuration from Alice installer"
        }

        if [ -f "$shell_config" ] && match=$(grep -Hn "$(unsubst_home "$env_file" | sed 's#\$#\\$#')" "$shell_config"); then
            info "It appears your shell config file ($shell_config) is already set up correctly as it contains the line:"
            echo
            info "$match"
            echo
            echo
            info "Just in case it isn't, here are the lines that need run when your shell starts to initialize Alice:"
            echo
            shell_config_code
            echo
        else
            info "To run 'alice' from your terminal, you'll need to add the following lines to your shell config file ($shell_config):"
            echo
            shell_config_code
            echo

            if [ "$should_update_shell_config" = "y" ] || y_or_n "Would you like these lines to be appended to $shell_config?"; then
                mkdir -p "$(dirname "$shell_config")"
                shell_config_code >> "$shell_config"
                echo
                success "Added Alice setup commands to $shell_config!"
                echo
                info "Restart your terminal for the changes to take effect."
                echo
            fi
        fi
    fi

    if ! [ "$install_tools" = "n" ] && ([ "$install_tools" = "y" ] || y_or_n "Would you like to install the OCaml compiler, ocamllsp, and ocamlformat?"); then
        if [ -z "${global+x}" ]; then
            echo "Installing tools to '$HOME/.alice/current'..."
            global_arg=""
        else
            echo "Installing tools to '$global'..."
            global_arg="--global=$global"
        fi
        if [ "$install_compiler_only" = "y" ]; then
            "$install_root/bin/alice" tools install --compiler-only "$global_arg"
        else
            "$install_root/bin/alice" tools install "$global_arg"
        fi
    fi

    echo "Restart your shell to get access to new commands."
    exit_message
    echo
}
main "$@"
