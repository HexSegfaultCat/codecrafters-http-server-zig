#!/bin/sh

set -m

COLOR_NONE="\033[0m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"

TEXT_PREFIX="${COLOR_NONE}[TEST]"
TEXT_FAIL="${COLOR_RED}Fail"
TEXT_SUCCESS="${COLOR_GREEN}Success"

TESTS_DIRECTORY="./tests"
SERVER_PORT=4221
TIMEOUT_SECONDS=3

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
echo "Pre-test setup... "
zig build
if [ -n "${1}" ]; then
  (zig build run -- --directory ./tmp 2>&1) &
else
  (zig build run -- --directory ./tmp &> /dev/null) &
fi

# Wait until server accepts connections
START_TIMESTAMP=$(date +%s)
while true; do
  CURRENT_TIMESTAMP=$(($(date +%s) - $START_TIMESTAMP))

  LISTENING_ENTRIES=$(ss -4tlnH sport $SERVER_PORT | wc -l)
  [ $LISTENING_ENTRIES -ge 1 ] && break;

  if [ $(($(date +%s) - $START_TIMESTAMP)) -gt $TIMEOUT_SECONDS ]; then
    echo "Server did not start in time, exiting"
    exit 1
  fi
  sleep 0.2
done

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

