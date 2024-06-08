STATUS_CODE=$(curl -s -w "%{response_code}" http://127.0.0.1:4221)
[ ${STATUS_CODE} == 200 ]

STATUS_CODE=$(curl -s -w "%{response_code}" http://127.0.0.1:4221/index.html)
[ ${STATUS_CODE} == 200 ]

STATUS_CODE=$(curl -s -w "%{response_code}" http://127.0.0.1:4221/asdfasdf)
[ ${STATUS_CODE} == 404 ]
