#!/usr/bin/env bats

function setup {
    dssh_path="${BATS_TEST_DIRNAME}/.."
    dssh_test_path="${BATS_TEST_DIRNAME}"
    temp_path=$(mktemp -d)

    PATH="${dssh_test_path}:${dssh_path}:${PATH}"

    LF=$'\n'
}

function teardown {
    rm -rf "${temp_path}"
}

@test "print help by -h/--help option" {
    expected_usage='Usage: dssh.sh [options...] [--] [command]'

    run dssh.sh -h
    [ "${status}" -eq 0 ]
    [ "${lines[1]}" == "${expected_usage}" ]

    run dssh.sh --help
    [ "${status}" -eq 0 ]
    [ "${lines[1]}" == "${expected_usage}" ]
}

@test "-d/--ssh option" {

    run dssh.sh -d user@host1 --ssh user@host2 echo hello
    [ "${status}" -eq 0 ]
}

@test "-f/--dests-file option" {
    echo "user@host1${LF}user@host2" > "${temp_path}/ssh.dests"

    run dssh.sh -f "${temp_path}/ssh.dests" echo hello
    [ "${status}" -eq 0 ]

    run dssh.sh --dests-file "${temp_path}/ssh.dests" echo hello
    [ "${status}" -eq 0 ]
}

@test "-n/--no-label option" {

    run dssh.sh -n --ssh user@host1 echo hello
    [ "${status}" -eq 0 ]

    run dssh.sh --no-label --ssh user@host1 echo hello
    [ "${status}" -eq 0 ]
}

@test "-o/--output-dir option" {

    run dssh.sh -o "${temp_path}/result" --ssh user@host1 echo hello
    [ "${status}" -eq 0 ]
    [ -f "${temp_path}/result/user@host1/out" ]

    run dssh.sh --output-dir "${temp_path}/result" --ssh user@host2 echo hello
    [ "${status}" -eq 0 ]
    [ -f "${temp_path}/result/user@host2/out" ]
}

@test "-a/--output-name option" {

    run dssh.sh -o "${temp_path}/result" -a 'out.txt' --ssh user@host1 echo hello
    [ "${status}" -eq 0 ]
    [ -f "${temp_path}/result/user@host1/out.txt" ]

    run dssh.sh --output-dir "${temp_path}/result" --output-name 'out.txt' --ssh user@host2 echo hello
    [ "${status}" -eq 0 ]
    [ -f "${temp_path}/result/user@host2/out.txt" ]
}

@test "-s/--silent option" {

    run dssh.sh -s --ssh user@host1 echo hello
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]

    run dssh.sh --silent --ssh user@host1 echo hello
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "use pipe" {

    run bash -c 'echo "hello" | dssh.sh --ssh user@host1 cat -'
    [ "${status}" -eq 0 ]
}
