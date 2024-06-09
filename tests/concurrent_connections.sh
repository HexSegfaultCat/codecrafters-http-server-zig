function run_nc() {
  NC_RESPONSE=$((sleep 5 && printf "GET / HTTP/1.1\r\n\r\n") | nc -q 1 localhost 4221)
  NC_STATUS=$?

  if [[ "${NC_STATUS}" != "0" || "${NC_RESPONSE}" != "HTTP/"* ]]; then
    exit 1
  fi
}

function run_curl() {
  CURL_RESPONSE=$(curl -vs --connect-timeout 1 --max-time 1 http://localhost:4221 2>&1)
  CURL_STATUS=$?

  HTTP_STATUS_LINE=$(echo "${CURL_RESPONSE}" | grep '^<' | sed 's/< //' | head -n 1)
  if [[ "${CURL_STATUS}" != "0" || "${HTTP_STATUS_LINE}" != "HTTP/"* ]]; then
    exit 1
  fi
}

# Connect to the server, wait, then send request, close and validate response
run_nc &
sleep 1

# While server is busy handling the previous connection try to fetch data again
run_curl

wait $(jobs -p)

