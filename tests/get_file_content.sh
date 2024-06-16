FILE_NAME=foobar
FILE_CONTENT="\
Minima sit est illum asperiores ut.
Est nam ut et perspiciatis quasi.
Aut libero accusamus perspiciatis expedita qui.
"
echo "${FILE_CONTENT}" >"./tmp/${FILE_NAME}"

CURL_RESPONSE=$(curl -s "http://localhost:4221/files/${FILE_NAME}")
CURL_STATUS=$?

if [[ "${CURL_STATUS}" != "0" || "${FILE_CONTENT}" != "${CURL_RESPONSE}"? ]]; then
	exit 1
fi
