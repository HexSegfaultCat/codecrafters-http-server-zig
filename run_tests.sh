#!/bin/sh

set -m # enable

COLOR_NONE="\033[0m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"

TEXT_PREFIX="${COLOR_NONE}[TEST]"
TEXT_FAIL="${COLOR_RED}Fail"
TEXT_SUCCESS="${COLOR_GREEN}Success"

TESTS_DIRECTORY="./tests"

function echo_info {
  echo -ne "${TEXT_PREFIX}${COLOR_YELLOW} $1"
}

function run_test() {
	echo_info "Running '${1}'... "

  FILE_PATH="${TESTS_DIRECTORY}/${1}"
  TEST_TIMEOUT=30

  case "${1}" in
    *.zig)
      TEST_OUTPUT=$(timeout ${TEST_TIMEOUT} zig test "${FILE_PATH}" 2>&1 <&-)
      ;;
    *.sh)
      TEST_OUTPUT=$(timeout ${TEST_TIMEOUT} /bin/sh -ex "${FILE_PATH}" 2>&1 <&-)
      ;;
    *) return ;;
  esac
	TEST_STATUS=$?

	if [ ${TEST_STATUS} -eq 0 ]; then
		echo -e "${TEXT_SUCCESS}"
    if [ -n "${2}" ]; then
      echo "${TEST_OUTPUT}"
    fi
	else
		echo -e "${TEXT_FAIL}"
		echo "${TEST_OUTPUT}"
		echo "----------------------"
	fi
}

function cleanup() {
  PIDS=$(jobs -pr)
  echo -ne "${COLOR_NONE}Post-test cleanup for PIDs ${PIDS}... "
  for job_pid in ${PIDS}; do
    pstree -p ${job_pid} | grep -oP '(?<=\()[0-9]+(?=\))' | xargs -r kill -9 2> /dev/null
  done
  echo "Done"
}

trap "cleanup" SIGINT SIGTERM EXIT

# Build and start the main app in background
echo -n "Pre-test setup... "
zig build
if [ -n "${1}" ]; then
  (zig build run -- --directory ./tmp 2>&1) &
else
  (zig build run -- --directory ./tmp &> /dev/null) &
fi
sleep 1
echo "Done"

if [ -n "${1}" ]; then
  # Run specified test file from `./tests/` in debug mode
  FILENAME=$(basename $1)
  run_test "${FILENAME}" DEBUG
else
  # Run all tests in non-debug mode (prints debug only on error)
  for test_file in $(ls -p ${TESTS_DIRECTORY} | grep -v /); do
    run_test "${test_file}"
  done
fi

