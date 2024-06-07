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

  case "${1}" in
    *.zig)
      TEST_OUTPUT=$(zig test "${FILE_PATH}" 2>&1 <&-)
      ;;
    *.sh)
      TEST_OUTPUT=$(/bin/sh -ex "${FILE_PATH}" 2>&1 <&-)
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

# Build and start the main app in background
zig build
if [ -n "${1}" ]; then
  (zig build run 2>&1) &
else
  (zig build run > /dev/null) &
fi
ZIG_APP_PID=$!
sleep 1

if [ -n "${1}" ]; then
  # Run specified test file from `./tests/` in debug mode
  FILENAME=$(basename $1)
  run_test "${FILENAME}" DEBUG
else
  # Run all tests in non-debug mode (prints debug only on error)
  for test_file in $(ls ${TESTS_DIRECTORY}); do
    run_test "${test_file}"
  done
fi

kill -9 $ZIG_APP_PID
