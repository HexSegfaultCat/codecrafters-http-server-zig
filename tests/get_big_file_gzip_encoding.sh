FILE_NAME=random-data.raw

mkdir -p "./tmp"
dd if=/dev/urandom of="./tmp/${FILE_NAME}" bs=1M count=100 status=progress

FILE_CHECKSUM=$(md5sum "./tmp/${FILE_NAME}" | awk '{print $1}')
CURL_RESPONSE_CHECKSUM=$(
  curl -s -H "Accept-Encoding: gzip" "http://localhost:4221/files/${FILE_NAME}" |
    gunzip |
    md5sum |
    awk '{print $1}'
)
CURL_STATUS=$?

rm "./tmp/${FILE_NAME}"

if [[ "${CURL_STATUS}" != "0" || "${FILE_CHECKSUM}" != "${CURL_RESPONSE_CHECKSUM}" ]]; then
  exit 1
fi
