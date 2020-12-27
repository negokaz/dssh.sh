#!/usr/bin/env bats

function setup {
    load '../node_modules/bats-support/load'
    load '../node_modules/bats-assert/load'

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
    assert_success
    assert_line --index 1 "${expected_usage}"

    run dssh.sh --help
    assert_success
    assert_line --index 1 "${expected_usage}"
}

@test "print version by -V/--version option" {
    expected_regexp='[0-9]+\.[0-9]+\.[0-9]+'

    run dssh.sh -V
    assert_success
    assert_output --regexp "${expected_regexp}"

    run dssh.sh --version
    assert_success
    assert_output --regexp "${expected_regexp}"
}

@test "width of help output is less than 80" {

    run dssh.sh --help
    diff <(echo "${output}") <(echo "${output}" | fold -w 80)
}

@test "-d/--ssh option" {

    run dssh.sh -d user@host1 --ssh user@host2 echo hello
    assert_success
}

@test "-f/--dests-file option" {
    echo "user@host1${LF}user@host2" > "${temp_path}/ssh.dests"

    run dssh.sh -f "${temp_path}/ssh.dests" echo hello
    assert_success

    run dssh.sh --dests-file "${temp_path}/ssh.dests" echo hello
    assert_success
}

@test "-f/--dests-file option parses unnormalized file" {
    cat - <<EOF > "${temp_path}/ssh.dests"
# comment
user@host1 # comment
  user@host2 # unnecessary spaces exit
# empty line

EOF

    run dssh.sh -f "${temp_path}/ssh.dests" echo hello
    assert_success
    assert_line --regexp '^user@host1\t| hello'
    assert_line --regexp '^user@host2\t| hello'

    run dssh.sh --dests-file "${temp_path}/ssh.dests" echo hello
    assert_success
    assert_line --regexp '^user@host1\t| hello'
    assert_line --regexp '^user@host2\t| hello'
}

@test "-S/--sequential option without interval" {

    run dssh.sh --ssh user@host1 --ssh user@host2 --sequential echo hello
    assert_success
    assert_line --index 0 --partial 'user@host1'
    assert_line --index 0 --partial 'hello'
    assert_line --index 1 --partial 'user@host2'
    assert_line --index 1 --partial 'hello'

    run dssh.sh --ssh user@host1 --ssh user@host2 -S echo hello
    assert_success
    assert_line --index 0 --partial 'user@host1'
    assert_line --index 0 --partial 'hello'
    assert_line --index 1 --partial 'user@host2'
    assert_line --index 1 --partial 'hello'
}

@test "-S/--sequential option with interval" {

    run dssh.sh --ssh user@host1 --ssh user@host2 --sequential 1 echo hello
    assert_success
    assert_line --index 0 --partial 'user@host1'
    assert_line --index 0 --partial 'hello'
    assert_line --index 1 --partial 'user@host2'
    assert_line --index 1 --partial 'hello'

    run dssh.sh --ssh user@host1 --ssh user@host2 -S 1 echo hello
    assert_success
    assert_line --index 0 --partial 'user@host1'
    assert_line --index 0 --partial 'hello'
    assert_line --index 1 --partial 'user@host2'
    assert_line --index 1 --partial 'hello'
}

@test "-n/--no-label option" {

    run dssh.sh -n --ssh user@host1 echo hello
    assert_success

    run dssh.sh --no-label --ssh user@host1 echo hello
    assert_success
}

@test "-o/--output-dir option" {

    run dssh.sh -o "${temp_path}/result" --ssh user@host1 echo hello
    assert_success
    assert [ -f "${temp_path}/result/user@host1/out" ]

    run dssh.sh --output-dir "${temp_path}/result" --ssh user@host2 echo hello
    assert_success
    assert [ -f "${temp_path}/result/user@host2/out" ]
}

@test "-a/--output-name option" {

    run dssh.sh -o "${temp_path}/result" -a 'out.txt' --ssh user@host1 echo hello
    assert_success
    assert [ -f "${temp_path}/result/user@host1/out.txt" ]

    run dssh.sh --output-dir "${temp_path}/result" --output-name 'out.txt' --ssh user@host2 echo hello
    assert_success
    assert [ -f "${temp_path}/result/user@host2/out.txt" ]
}

@test "-s/--silent option" {

    run dssh.sh -s --ssh user@host1 echo hello
    assert_success
    assert [ -z "${output}" ]

    run dssh.sh --silent --ssh user@host1 echo hello
    assert_success
    assert [ -z "${output}" ]
}

@test "use pipe" {

    run bash -c 'echo "hello" | dssh.sh --ssh user@host1 --ssh user@host2 cat -'
    assert_success
    assert_line --partial 'user@host1'
    assert_line --partial 'user@host2'
}

@test "use pipe with --sequential" {

    run bash -c 'echo "hello" | dssh.sh --ssh user@host1 --ssh user@host2 --sequential 1 cat -'
    assert_success
    assert_line --index 0 --partial 'user@host1'
    assert_line --index 1 --partial 'user@host2'
}
