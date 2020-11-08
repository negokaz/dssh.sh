#!/bin/bash

set -o allexport

readonly script_name=$(basename "$0")

function print_usage {
    cat - <<END_OF_USAGE
ssh client script for distributed systems
Usage: ${script_name} [options...] [--] [command]
<options>:
    -h, --help                  Print help

    -d, --ssh <destination>     Set destinations

    -f, --dests-file <file>     Read destinations from the given file
                                which is written one destination per line

    -S, --sequential <interval> Exexute command sequentially
                                (default interval: 0)

    -n, --no-label              Output without destination label

    -o, --output-dir <path>     Save stdout from servers to files
                                in the given directory

    -a, --output-name <name>    Save stdout as the given file name in output-dir
                                (default: out)

    -s, --silent                Don't output anything

    -v, --verbose               Describe what happened in detail

        --                      Process following arguments as commands

<command>:
    execute in the destinations

Examples:
    # Watch log being in destination servers
    ${script_name} --ssh user@server1 --ssh user@server2 tail -F /var/log/messages

    # Watch log with destination file
    ${script_name} -f ssh.dests tail -F /var/log/messages

    # Collect ERROR logs on server and sort they on local
    ${script_name} -f ssh.dests --no-label bash -c 'cat /var/log/messages |
        grep ERROR' | sort | less -R

    # Publish a file to destination servers
    cat source.txt | ${script_name} -f ssh.dests tee /tmp/dest.txt

    # Fetch files from destination servers
    ${script_name} -f ssh.dests -o out -a messages.log --silent cat /var/log/messages
END_OF_USAGE
}

# [Require]
ssh_dests=''

# [Require]
ssh_command=''

# [Option]
sequential='false'

# [Option]
sequential_interval=0

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
    if [ -z "${ssh_dests}" -o -z "${ssh_command}" ]
    then
        {
            echo '[ERROR] Destinations and command is required'
            echo
            print_usage
        } >&2
        exit 1
    fi

    # other props
    if test -p /dev/stdin
    then
        pipe_is_enabled='true'
    else
        pipe_is_enabled='false'
    fi

    parallelism=$(echo "${ssh_dests}" | wc -l)

    if ${verbose}
    then
        ssh_options='-o LogLevel=VERBOSE'
    fi

    dispatch_command_to_dests
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
            '-S' | '--sequential' )
                sequential='true'
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    sequential_interval=$2
                    shift 2
                else
                    shift 1
                fi
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
                    echo "[ERROR] Unknown option: $1"
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
                ssh_command="${ssh_command} '$1'"
                shift 1
                ;;
        esac
    done

    # normalize input
    ssh_dests=$(echo "$ssh_dests" | tr ' ' '\n' | sed -E '/^$/d')
}

readonly temp_dir="$(mktemp -d)"

function on_interrupt_signal {
    # kill all process group
    /usr/bin/env kill -PIPE -- $(jobs -p) &> /dev/null

    # cancel succeeding commands when sequential mode is enabled
    exit 0
}

trap on_interrupt_signal SIGHUP SIGINT SIGQUIT SIGTERM

function on_exit {
    rm -rf "${temp_dir}"
}

trap on_exit EXIT

function dispatch_command_to_dests {

    if ${sequential}
    then
        if ${pipe_is_enabled}
        then
            local stdin_file="${temp_dir}/${dest}.stdin"
            cat - > "${stdin_file}"
        else
            local stdin_file=""
        fi
        while read color dest head_dest
        do
            if [[ "${dest}" != "${head_dest}" ]]
            then
                sleep ${sequential_interval}
            fi
            # spawn subprocess
            (exec_command_via_ssh ${color} ${dest} "${stdin_file}")
        done < <(create_exec_args)
    else
        # execute in parallel
        while read color dest head_dest
        do
            if ${pipe_is_enabled}
            then
                local stdin_fifo="${temp_dir}/${dest}.stdin"
                mkfifo "${stdin_fifo}"
            else
                local stdin_fifo=""
            fi
            exec_command_via_ssh ${color} ${dest} "${stdin_fifo}" &
        done < <(create_exec_args)

        if ${pipe_is_enabled}
        then
            # broadcast stdin to dest
            tee $(find "${temp_dir}" -type p) > /dev/null
        fi
        wait
    fi
}

function create_exec_args {
    echo "${ssh_dests}" | awk '
    NR == 1 {
      head_dest = $0
    }
    {
        dest  = $0
        color = (NR % 6) + 1

        # arguments for exec_command_via_ssh
        print color, dest, head_dest
    }'
}

function exec_command_via_ssh {
    local color="$1" dest="$2" stdin="$3"

    if [ -z "${stdin}" ]
    then
        exec < /dev/null
    else
        exec < "${stdin}"
    fi
    if [ -z "${output_dir}" ]
    then
        output_file=/dev/null
    else
        mkdir -p    "${output_dir}/${dest}"
        output_file="${output_dir}/${dest}/${output_name}"
    fi
    if ${label_is_enabled}
    then
        stdout_label="\033[3${color}m${dest}\t|\033[0m "
        stderr_label="\033[3${color}m${dest}\t\033[31m!\033[0m "
    else
        stdout_label=''
        stderr_label=''
    fi

    if ${silent}
    then
        exec 1>/dev/null 2>/dev/null
    fi

    # to enable ssh-askpass
    export DISPLAY="${DISPLAY:-dummy:0}"

    exec ssh ${ssh_options} "${dest}" "${ssh_command}" \
        1> >(tee "${output_file}" | awk -v label="${stdout_label}" '{ print label$0; fflush() }' >&1) \
        2> >(awk -v label="${stderr_label}" '{ print label$0; fflush() }' >&2)
}

main "$@"
