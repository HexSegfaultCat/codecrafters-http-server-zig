FILE_NAME=foobar123
FILE_CONTENT="Foobar123"

# Save file
STATUS_CODE=$(curl -s -w "%{response_code}" -X POST -d "${FILE_CONTENT}" http://127.0.0.1:4221/files/${FILE_NAME})
if [[ "${STATUS_CODE}" != "201" ]]; then
	exit 1
fi

# Read file
CURL_RESPONSE=$(curl -s "http://localhost:4221/files/${FILE_NAME}")
CURL_STATUS=$?
if [[ "${CURL_STATUS}" != "0" || "${FILE_CONTENT}" != "${CURL_RESPONSE}" ]]; then
	exit 1
fi
