#!/usr/bin/env bats
# vim: ft=bats:list:ts=8:sts=4:sw=4:et:ai:si:

set -u

load "${TEST_DIR}/lib/bats-support/load.bash"
load "${TEST_DIR}/lib/bats-assert/load.bash"

FILE="$(basename "${BATS_TEST_FILENAME}" .bats):"

#declare stderr
CSCLI="${BIN_DIR}/cscli"

fake_log() {
    for _ in $(seq 1 6) ; do
        echo "$(LC_ALL=C date '+%b %d %H:%M:%S ')"'sd-126005 sshd[12422]: Invalid user netflix from 1.1.1.172 port 35424'
    done;
}

setup_file() {
    #shellcheck source=../lib/assert-crowdsec-not-running.sh
    . "${TEST_DIR}/lib/assert-crowdsec-not-running.sh"
    # we reset config and data, but run the daemon only in the tests that need it
    "${TEST_DIR}/instance-data" load
}

teardown() {
    "${TEST_DIR}/instance-crowdsec" stop
}

#----------

@test "$FILE 1.1.1.172 has been banned" {
    tmpfile=$(mktemp)
    touch "${tmpfile}"
    echo -e "---\nfilename: $tmpfile\nlabels:\n  type: syslog\n" >> "${CONFIG_DIR}/acquis.yaml"

    "${TEST_DIR}/instance-crowdsec" start
    sleep 2s
    fake_log >> "${tmpfile}"
    sleep 2s
    rm -f -- "${tmpfile}"
    run "${CSCLI}" decisions list -o json
    assert_success
    run jq -r '.[].decisions[0].value' <(echo "$output")
    assert_success
    assert_output '1.1.1.172'
}
