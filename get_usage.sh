#!/bin/bash
################################################################################

# login to duke-energy and get energy usage

################################################################################

# user and encrypted pass
user="dayalpavan@gmail.com"
# echo "passwd" | openssl enc -aes-256-cbc -a -salt -iter 1 -in - -out -
pass_enc="U2FsdGV   REDACTED FOR SECURITY   S4bBaDZC8="

# set the date to a sunday "MM / DD / YYYY"
request_data='{
    "MeterNumber":"ELECTRIC - 32 redacted 9",
    "Date":"08 / 02 / 2020",
    "Graph":"hourlyEnergyUse",
    "BillingFrequency":"Week",
    "GraphText":"Hourly Energy Usage ",
    "ActiveDate":"07/31/2020"
}'

# whether to login and/or save cookies
login=0
save_login=0
save_login_file="duke_login.txt"
load_login=1

################################################################################

cookies=()
auth_cookies=()
usage_cookies=()

if [ $load_login -eq 0 ] && [ $login -eq 0 ]; then
    echo "error: either login or load login cookies" 1>&2
    exit 1
fi

if [ $login -eq 0 ] && [ $save_login -ne 0 ]; then
    echo "error: cant save login if not logged in" 1>&2
    exit 1
fi

separate_cookies() {
    echo -e "$@" \
    | grep -Eo "set-cookie:.+" \
    | sed -r "s/set-cookie:\s+//g" \
    | sed "s/\r/;/g" \
    | sed "s/;/\n/g" \
    | sed "/^$/d" \
    | sed -r "s/^\s+//" \
    | sort \
    | uniq
}

print_cookies() {
    echo -n "$1"
    shift
    echo "${@/#/; }"
}

get_cookies() {
    echo "getting session id" 1>&2
    cookies=$(curl -i \
        -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:79.0) Gecko/20100101 Firefox/79.0' \
        -H 'Accept: text/html' \
        -H 'Accept-Language: en-US,en' \
        -H 'Referer: https://www.duke-energy.com/my-account/sign-in' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -H 'Origin: https://www.duke-energy.com' \
        -H 'Cookie:' \
        -H 'DNT: 1' \
        -H 'Connection: keep-alive' \
        -H 'Upgrade-Insecure-Requests: 1' \
        -H 'TE: Trailers' \
        --data-raw 'userId=aaa&userPassword=aaaaaaaa&pageId=416298df-33d4-4347-9d27-08f66d922a96' \
        'https://www.duke-energy.com/form/SignIn/GetAccountValidationMessage' \
    )
    IFSBAK=$IFS
    IFS=$'\n'
    cookies=( $(separate_cookies "$cookies") )
    IFS=$IFSBAK
    c=$(print_cookies "${cookies[@]}")
    echo 1>&2


    # TODO put curl dataraw in temp file and delete file, as any other user
    # on the system could see it plain text if they run `ps` at the right time
    echo "logging in to duke energy" 1>&2
    dec_fail=1
    while [ "$dec_fail" -eq 1 ]; do
        pass=$(echo $pass_enc | openssl enc -d -aes-256-cbc -a -iter 1 -in - -out -)
        dec_fail=$?
    done
    auth_cookies=$(curl -i \
        -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:79.0) Gecko/20100101 Firefox/79.0' \
        -H 'Accept: text/html' \
        -H 'Accept-Language: en-US,en' \
        -H 'Referer: https://www.duke-energy.com/my-account/sign-in' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -H 'Origin: https://www.duke-energy.com' \
        -H "Cookie: $c" \
        -H 'DNT: 1' \
        -H 'Connection: keep-alive' \
        -H 'Upgrade-Insecure-Requests: 1' \
        -H 'TE: Trailers' \
        --data-raw "userId=$user&userPassword=$pass&pageId=416298df-33d4-4347-9d27-08f66d922a96" \
        'https://www.duke-energy.com/form/SignIn/GetAccountValidationMessage' \
    )
    unset pass
    IFSBAK=$IFS
    IFS=$'\n'
    auth_cookies=( $(separate_cookies "$auth_cookies") )
    IFS=$IFSBAK
    c2=$(print_cookies "${auth_cookies[@]}")
    echo 1>&2


    echo "navigating to energy usage page" 1>&2
    usage_cookies=$(curl -i \
        -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:79.0) Gecko/20100101 Firefox/79.0' \
        -H 'Accept: text/html' \
        -H 'Accept-Language: en-US,en' \
        -H 'Referer: https://www.duke-energy.com/my-account' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -H 'Origin: https://www.duke-energy.com' \
        -H "Cookie: $c; $c2" \
        -H 'DNT: 1' \
        -H 'Connection: keep-alive' \
        -H 'Upgrade-Insecure-Requests: 1' \
        -H 'TE: Trailers' \
        'https://www.duke-energy.com/my-account/usage-analysis'
    )
    IFSBAK=$IFS
    IFS=$'\n'
    usage_cookies=( $(separate_cookies "$usage_cookies") )
    IFS=$IFSBAK
    echo 1>&2
}

save_cookies() {
    file=$1
    print_cookies "${cookies[@]}" > $file
    print_cookies "${auth_cookies[@]}" >> $file
    print_cookies "${usage_cookies[@]}" >> $file
}

load_cookies() {
    file=$1
    IFSBAK=$IFS
    IFS=$'\n'
    cookies=( $(head -n 1 $file | sed "s/; /\n/g") )
    auth_cookies=( $(head -n 2 $file | tail -n 1 | sed "s/; /\n/g") )
    usage_cookies=( $(tail -n 1 $file | sed "s/; /\n/g") )
    IFS=$IFSBAK
}

################################################################################

if [ $login -ne 0 ]; then
    get_cookies
fi

if [ $save_login -ne 0 ]; then
    save_cookies $save_login_file
fi

if [ $load_login -ne 0 ]; then
    load_cookies $save_login_file
fi

c=$(print_cookies "${cookies[@]}" "${auth_cookies[@]}" "${usage_cookies[@]}")

echo "getting energy usage data" 1>&2
data=$(curl -i \
    -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:79.0) Gecko/20100101 Firefox/79.0' \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Accept-Language: en-US,en' \
    -H 'Referer: https://www.duke-energy.com/my-account/usage-analysis' \
    -H 'Content-Type: application/json' \
    -H 'Origin: https://www.duke-energy.com' \
    -H "Cookie: $c" \
    -H 'DNT: 1' \
    -H 'Connection: keep-alive' \
    -H 'Upgrade-Insecure-Requests: 1' \
    -H 'TE: Trailers' \
    --data-raw "$request_data" \
    'https://www.duke-energy.com/api/UsageAnalysis/GetUsageChartData'
)

data=$(echo -e "$data" | awk 'a == 0 {if ($0 ~ /\{/) {a = 1}} a == 1 {print}')

if echo $data | jq .Status | grep -io err > /dev/null; then
    echo "error: couldnt get data (try logging in again?)" 1>&2
    exit 2
fi
energy=( $(echo $data | jq .meterData.Electric[]) )
n=${#energy[@]}
date=( $(echo $data | jq .graphDates[] -r | tail -n $n | cut -d"T" -f1 | sed "s/-//g") )
time=( $(echo $data | jq .graphDates[] -r | tail -n $n | cut -d"T" -f2 | cut -d":" -f1) )

for i in ${!energy[@]}; do
    echo "${date[$i]},${time[$i]},${energy[$i]}"
done
