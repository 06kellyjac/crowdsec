
# What is this?

This directory contains scripts for functional testing. The tests are run with
the [bats-core](https://github.com/bats-core/bats-core) framework, which is an
active fork of the older BATS (Bash Automated Testing System).

The goal is to be cross-platform but not explicitly test the packaging system
or service management. Those parts are specific to each distribution and are
tested separately (triggered by crowdsec releases, but they run in other
repositories).

XXX TODO

### cscli

| Feature               | Covered        | Notes                      |
| :-------------------- | :------------- | :------------------------- |
| `cscli alerts`        | -              |                            |
| `cscli bouncers`      | 10_bouncers    |                            |
| `cscli capi`          | 01_base        | `status` only              |
| `cscli collections`   | 20_collections |                            |
| `cscli config`        | 01_base        | minimal testing (no crash) |
| `cscli dashboard`     | -              | docker inside docker 😞    |
| `cscli decisions`     | 98_ipv[46]     |                            |
| `cscli hub`           | -              |                            |
| `cscli lapi`          | 01_base        |                            |
| `cscli machines`      | 30_machines    |                            |
| `cscli metrics`       | -              |                            |
| `cscli parsers`       | -              |                            |
| `cscli postoverflows` | -              |                            |
| `cscli scenarios`     | -              |                            |
| `cscli simulation`    | 50_simulation  |                            |
| `cscli version`       | 01_base        |                            |

### crowdsec

| Feature                        | Covered      | Notes                                      |
| :----------------------------- | :----------- | :----------------------------------------- |
| `systemctl` start/stop/restart | -            |                                            |
| agent behaviour                | 40_cold-logs | minimal testing  (simple ssh-bf detection) |
| forensic mode                  | 40_cold-logs | minimal testing (simple ssh-bf detection)  |
| starting only LAPI             | -            |                                            |
| starting only agent            | -            |                                            |
| prometheus testing             | -            |                                            |

### API


| Feature            | Covered      | Notes        |
| :----------------- | :----------- | :----------- |
| alerts GET/POST    | 98_ipv[46]   |              |
| decisions GET/POST | 98_ipv[46]   |              |


# How to use it

Run `make clean bats-all` to perform a test build + run.

To repeat test runs without rebuilding crowdsec, use `make bats-test`.


# How does it work?

In BATS, you write tests in the form of Bash functions that have names. You can
do most things that you can normally do in a shell function. If there is any
error condition, the test fails. A set of functions is provided to implement
assertions, and a mechanism of `setup`/`teardown` is provided a the level of
individual tests (functions) or group of tests (files).

The stdout/stderr of the commands within the test function are captured by
bats-core and will only be shown if the test fails. If you want to always print
something to debug your test case, you can redirect the output to the file
descriptor 3:

```
@test "mytest" {
   echo "hello world!" >&3
   run some-command
   assert_success
   echo "goodbye." >&3
}
```

If you do that, please remove it once the test is finished, because this practice breaks the test protocol.

You can find here the documentation for the main framework and the plugins we use in this test suite:

 - [bats-core tutorial](https://bats-core.readthedocs.io/en/stable/tutorial.html)
 - [bats-assert](https://github.com/bats-core/bats-assert)
 - [bats-support](https://github.com/bats-core/bats-support)
 - [bats-file](https://github.com/bats-core/bats-file)

> As it often happens with open source, the first results from search engines refer to the old, unmaintained forks.
> Be sure to use the links above to find the good versions.

Since bats-core is [TAP (Test Anything Protocol)](https://testanything.org/)
compliant, its output is in a standardized format. It can be integrated with a
separate [tap reporter](https://www.npmjs.com/package/tape#pretty-reporters) or
included in a larger test suite. The TAP specification is pretty minimalist and
some glue may be needed.


Other tools that you can find useful:

 - [mikefarah/yq](https://github.com/mikefarah/yq) - to parse and update YAML files on the fly
 - [aliou/bats.vim](https://github.com/aliou/bats.vim) - for syntax highlighting (use bash otherwise)

# setup and teardown

If you have read the bats-core tutorial linked above, you are aware of the
`setup` and `teardown` functions.

What you may have overlooked is that the script body outside the functions is
executed multiple times, so we have to be careful of what we put there.

Here we have a look at the execution flow with two tests:

```
echo "begin" >&3

setup_file() {
        echo "setup_file" >&3
}

teardown_file() {
        echo "teardown_file" >&3
}

setup() {
        echo "setup" >&3
}

teardown() {
        echo "teardown" >&3
}

@test "test 1" {
        echo "test #1" >&3
}

@test "test 2" {
        echo "test #2" >&3
}

echo "end" >&3
```

The above test suite produces the following output:

```
begin
end
setup_file
begin
end
 ✓ test 1
setup
test #1
teardown
begin
end
 ✓ test 2
setup
test #2
teardown
teardown_file
```

See how "begin" and "end" are repeated three times each? The code outside
setup/teardown/test functions is really executed three times (more as you add
more tests). You can put there variables or function definitions, but
`setup_file()` is the place for any code with side effects.


# Testing crowdsec

## Fixtures

For the purpose of functional tests, crowdsec and its companions (cscli, plugin
notifiers, bouncers) are installed in a local environment, which means tests should
not install or touch anything outside a `./tests/local` directory. This includes
binaries, configuration files, databases, data downloaded from internet, logs...
The use of `/tmp` is tolerated, `./local/tmp` is even better.

When built with `make bats-build`, the binaries will look there by default for
their configuration and data needs. So you can run `./local/bin/cscli` from
a shell with no need for further parameters.

To set up the installation described above we provide a couple of scripts,
`instance-data` and `instance-crowdsec`. They manage fixture and background
processes; they are meant to be used in setup/teardown in several ways,
according to the specific needs of the group of tests in the file.

 - `instance-data make`

   Creates a tar file in `./local-init/init-config-data.tar`.
   The file contains all the configuration, hub and database files needed
   to restore crowdsec to a known initial state.
   Things like `machines add ...`, `capi register`, `hub update`, `collections
   install crowdsecurity/linux` are executed here so they don't need to be
   repeated for each test or group of tests.

 - `instance-data load`

   Extracts the files created by `instance-data make` for use by the local
   crowdsec instance. Crowdsec must not be running while this operation is
   performed.

 - `instance-crowdsec [ start | stop ]`

   Runs (or stops) crowdsec as a background process. PID and lockfiles are
   written in `./local/var/run/`.


Here are some ways to use the two scripts.

 - case 1: load a fresh crowsec instance + data for each test (01_base, 10_bouncers, 20_collections...)

    This offers the best isolation, but the tests run slower. More importantly,
    since there is no concept of "grouping" tests in bats-core with the exception
    of files, if you need to perform some setup that is common to two or more
    tests, you will have to repeat the code.

 - case 2: load a fresh set of data for each test, but run crowdsec only for
   the tests that need it, possibly after altering the configuration
   (02_nolapi, 03_noagent, 04_nocapi, 40_live-ban)

    This is useful because: 1) you sometimes don't want crowdsec to run, for
    example when testing `cscli`, and if you need to, it allows you to tweak the
    configuration inside the test function before running `crowdsec`. See how we
    use `yq` to change the YAML files to that effect.

 - case 3: run crowdsec with the same set of configuration+data once, for all
   the tests (50_simulation, 98_ipv4, 98_ipv6)

     This offers no isolation across tests, which over time could break more
     often as result, but you can rely on the test order to test more complex
     scenarios with a reasonable performance and the least amount of code.


## stdout and stderr

XXX TODO


# How to contribute

XXX TODO

