PLAIN_CONTENT=some-example-string

CURL_RESPONSE=$(curl -s -H "Accept-Encoding: gzip" "http://localhost:4221/echo/${PLAIN_CONTENT}" | gunzip)
CURL_STATUS=$?

if [[ "${CURL_STATUS}" != "0" || "${PLAIN_CONTENT}" != "${CURL_RESPONSE}" ]]; then
  exit 1
fi
