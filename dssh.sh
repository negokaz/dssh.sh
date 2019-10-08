#!/bin/bash

readonly script_name=$(basename "$0")

function print_usage {
    cat - <<END_OF_USAGE
ssh client script for distributed systems
Usage: ${script_name} [options...] [--] [command]
<options>:
    -h, --help                  Print help
    -d, --ssh <destination>     Set destinations
    -f, --dests-file <file>     Read destinations from the given file which is written one destination per line
    -n, --no-label              Output without destination label
    -o, --output-dir <path>     Save stdout from servers to files in the given directory
    -a, --output-name <name>    Save stdout as the given file name in output-dir
                                (default: out)
    -s, --silent                Don't output anything
    -v, --verbose               Describe what happened in detail
        --                      Process following arguments as commands
<command>:
    execute in the destinations

Examples:
    # Watch log being in destination servers
    ${script_name} --ssh user@26.10.10.10 --ssh user@26.10.10.11 tail -F /var/log/messages

    # Watch log with destination file
    ${script_name} -f ssh.dests tail -F /var/log/messages

    # Collect ERROR logs on server and sort they on local
    ${script_name} -f ssh.dests --no-label bash -c 'cat /var/log/messages | grep ERROR' | sort | less -R

    # Publish a file to destination servers
    cat source.txt | ${script_name} -f ssh.dests tee /tmp/dest.txt

    # Fetch files from destination servers
    ${script_name} -f ssh.dests -o out -a messages.log --silent cat /var/log/messages
END_OF_USAGE
}

# [Require]
ssh_dests=''

# [Require]
command=''

# [Option]
label_is_enabled='true'

# [Option]
output_dir=''

# [Option]
output_name='out'

# [Option]
silent='false'

# [Option]
verbose='false'

# [Option]
help='false'

# true if pipe is enabled
pipe_is_enabled='false'

# equals number of ssh_dests
parallelism=-1

# set when verbose mode
ssh_options=''

function main {

    parse_arguments "$@"

    if ${help}
    then
        print_usage
        exit 0
    fi
    
    # validate arguments
    if [ -z "${ssh_dests}" -o -z "${command}" ]
    then
        print_usage
        exit 1
    fi

    # other props
    if tty -s
    then
        pipe_is_enabled='false'
    else
        pipe_is_enabled='true'
    fi

    parallelism=$(echo "${ssh_dests}" | wc -l)
    
    if ! ${verbose}
    then
        ssh_options='-o LogLevel=QUIET'
    fi

    execute_on_sshs
}

function parse_arguments {
    # parse options
    while [ $# -gt 0 ]
    do
        case "$1" in
            '-h' | '--help' )
                help='true'
                shift 1
                ;;
            '-d' | '--ssh' )
                ssh_dests="${ssh_dests}"$'\n'"$2"
                shift 2
                ;;
            '-f' | '--dests-file' )
                ssh_dests="${ssh_dests}"$'\n'"$(cat "$2")"
                shift 2
                ;;
            '-n' | '--no-label' )
                label_is_enabled='false'
                shift 1
                ;;
            '-o' | '--output-dir' )
                output_dir="$2"
                shift 2
                ;;
            '-a' | '--output-name' )
                output_name="$2"
                shift 2
                ;;
            '-s' | '--silent' )
                silent='true'
                shift 1
                ;;
            '-v' | '--verbose' )
                verbose='true'
                shift 1
                ;;
            '--' )
                shift 1
                break
                ;;
            -*)
                {
                    echo "Unknown option: $1"
                    echo
                    print_usage
                } >&2
                exit 1
                ;;
            '')
                # skip
                shift 1
                ;;
            *)
                break
                ;;
        esac
    done
    # parse commands
    while [ $# -gt 0 ]
    do
        case "$1" in
            '')
                # skip
                shift 1
                ;;
            *)
                command="${command} '$1'"
                shift 1
                ;;
        esac
    done

    # normalize input
    ssh_dests=$(echo "$ssh_dests" | tr ' ' '\n' | sed -E '/^$/d' | sort | uniq)
}

temp_dir="$(mktemp -d)"

function on_exit {
    # kill all child processes
    /usr/bin/env kill -PIPE -- -$$
    rm -rf "${temp_dir}"
}

trap 'on_exit' EXIT

function execute_on_sshs {

    if ${pipe_is_enabled}
    then
        echo "${ssh_dests}" | xargs -I %DEST% mkfifo "${temp_dir}/%DEST%.stdin"
    fi

    # execute command via ssh
    echo "${ssh_dests}" | awk '{ print (NR % 6) + 1, $0 }' | xargs -I %COLOR_AND_DEST% -P ${parallelism} \
    env \
        pipe_is_enabled="${pipe_is_enabled}" \
        label_is_enabled="${label_is_enabled}" \
        color_and_dest="%COLOR_AND_DEST%" \
        temp_dir="${temp_dir}" \
        output_dir="${output_dir}" \
        output_name="${output_name}" \
        silent="${silent}" \
        ssh_options="${ssh_options}" \
        ssh_command="${command}" \
    bash -c '
        color_and_dest=(${color_and_dest})
        color="${color_and_dest[0]}"
        dest="${color_and_dest[1]}"
        if ${pipe_is_enabled}
        then
            input="${temp_dir}/${dest}.stdin"
        else
            input=/dev/null
        fi
        if [ -z "${output_dir}" ]
        then
            output_file=/dev/null
        else
            mkdir -p    "${output_dir}/${dest}"
            output_file="${output_dir}/${dest}/${output_name}"
        fi
        if ${silent}
        then
            stdout=/dev/null
            stderr=/dev/null
        else
            stdout=/dev/stdout
            stderr=/dev/stderr
        fi
        if ${label_is_enabled}
        then
            stdout_label="\033[3${color}m${dest}\t|\033[0m "
            stderr_label="\033[3${color}m${dest}\t\033[31m!\033[0m "
        else
            stdout_label=''
            stderr_label=''
        fi

        cat "${input}" | ssh ${ssh_options} "${dest}" "${ssh_command}" \
            1> >(tee "${output_file}" | awk -v label="${stdout_label}" "{ print label\$0; fflush() }" > "${stdout}") \
            2> >(awk -v label="${stderr_label}" "{ print label\$0; fflush() }" > "${stderr}")
    ' &

    if ${pipe_is_enabled}
    then
        # broadcast stdin to dest
        tee $(find "${temp_dir}" -type p) > /dev/null
    fi
    wait
}

main "$@"
