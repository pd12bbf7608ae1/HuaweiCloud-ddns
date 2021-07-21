#!/bin/bash

# debug=1 # 开启debug

# 用户账户信息
accountName='hwexample' # IAM用户所属帐号名
IAMUserName='example' # IAM用户名 
IAMUserPassword='example' # IAM用户密码
defaultTTL='300' # ttl
historyFile='/root/.iphistory_huawei' # 历史文件

dnsEndPoint='https://dns.myhuaweicloud.com'
IAMEndPoint='https://iam.myhuaweicloud.com'

fontRed='\033[31m'
fontGreen='\033[32m'
fontBlue='\033[36m'
fontNormal='\033[0m'

function echoRed() {
    echo -e "${fontRed}${*}${fontNormal}"
}
function echoBlue() {
    echo -e "${fontBlue}${*}${fontNormal}"
}
function echoGreen() {
    echo -e "${fontGreen}${*}${fontNormal}"
}

function debug() {
    if [ "$debug" == "1" ]; then
        echo "$*" 
    fi
}

# HUAWEI API
function GetIAMToken() {
    local accountName="$1"
    local IAMUserName="$2"
    local IAMUserPassword="$3"
    local postBody="{
    \"auth\": {
        \"identity\": {
            \"methods\": [
                \"password\"
            ],
            \"password\": {
                \"user\": {
                    \"domain\": {
                        \"name\": \"${accountName}\"
                    },
                    \"name\": \"${IAMUserName}\",
                    \"password\": \"${IAMUserPassword}\"
                }
            }
        },
        \"scope\": {
            \"project\": {
                \"name\": \"cn-north-4\"
            }
        }
    }
    }"
    
    echoBlue "获取token..." 1>&2
    local curlInfo curlCode
    debug "$postBody" 1>&2
    curlInfo=$(curl -i -X "POST" -w "Code:%{response_code}" -H "Content-Type: application/json;charset=utf8" -d "${postBody}" "${IAMEndPoint}/v3/auth/tokens")
    curlCode="$?"
    debug "$curlInfo" 1>&2
    if [ "$curlCode" -ne 0 ]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | tr -d "\n" | sed -e "s/.*Code://g")
        if [ "$responseCode" != "201" ]; then    
            echoRed "响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            local IAMToken=$(echo "${curlInfo}" | grep "^X-Subject-Token:" | sed -e 's/X-Subject-Token: //g')
            if [ -z "${IAMToken}" ]; then
                echoRed "IAMToken为空" 1>&2
                return 1
            else
                echoGreen "IAMToken获取成功" 1>&2
                echo "${IAMToken}"
                return 0
            fi
        fi
    fi
}
function GetZoneId() {
    local zone="$1"
    echoBlue "查询zoneId..." 1>&2
    if [ -z $(echo "$zone" | grep "\.$") ]; then
        local zone="${zone}."
    fi
    local curlInfo curlCode
    curlInfo=$(curl -X "GET" -w "Code:%{response_code}" -H "Content-Type: application/json;charset=utf8" -H "X-Auth-Token: ${IAMToken}" "${dnsEndPoint}/v2/zones?type=public&name=${zone}")
    curlCode="$?"
    debug "$curlInfo" 1>&2
    if [ "$curlCode" -ne 0 ]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | tr -d "\n" | sed -e "s/.*Code://g")
        if [ "$responseCode" != "200" ]; then
            echoRed "响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            local zoneId=$(echo "${curlInfo}" | sed -e 's/Code:...//g' -e 's/.*\"zones\":\[//g' -e 's/\"masters\":\[[^]]*\],//g' -e 's/\].*//g' -e 's/},{/}\n{/g' | grep "\"name\":\"${zone}\"" | sed -n -e 's/.*\"id\":\"\([[:alnum:]]\+\)\".*/\1/p')
            if [[ -z "${zoneId}" || $(echo "${zoneId}" | wc -l) -ne 1 ]]; then
                echoRed "zoneId为空或者有多个匹配" 1>&2
                return 1
            else
                echoGreen "zoneId获取成功" 1>&2
                echo "${zoneId}"
                return 0
            fi
        fi
    fi
}
function GetRecordSetId() {
    local zoneId="$1"
    local zone="$2"
    local name="$3"
    local type="$4"
    echoBlue "查询recordSetId... " 1>&2
    if [ -z $(echo "$zone" | grep "\.$") ]; then
        zone="${zone}."
    fi
    if [ -z $(echo "$name" | grep "\.$") ]; then
        name="${name}."
    fi
    if [ -z "$type" ]; then
        type="A"
    fi
    local curlInfo curlCode
    curlInfo=$(curl -X "GET" -w "Code:%{response_code}" -H "Content-Type: application/json;charset=utf8" -H "X-Auth-Token: ${IAMToken}" "${dnsEndPoint}/v2/zones/${zoneId}/recordsets?type=${type}")
    curlCode="$?"
    debug "$curlInfo" 1>&2
    if [ "$curlCode" -ne 0 ]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | tr -d "\n" | sed -e "s/.*Code://g")
        if [ "$responseCode" != "200" ]; then
            echoRed "响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            local recordSetId=$(echo "${curlInfo}" | sed -e 's/Code:...//g' -e 's/\"records\":\[[^]]*\],//g' -e 's/.*\"recordsets\":\[//g' -e 's/\],.*//g' -e 's/},{/}\n{/g' | grep "\"name\":\"${name}${zone}\"" | sed -n -e 's/.*\"id\":\"\([[:alnum:]]\+\)\".*/\1/p')
            if [[ -z "${recordSetId}" ]]; then
                echoRed "recordSetId为空" 1>&2
                return 2
            else
                echoGreen "recordSetId获取成功" 1>&2
                echo "${recordSetId}"
                return 0
            fi
        fi
    fi
}
function DeleteRecordSet() {
    local zoneId="$1"
    local recordSetId="$2"
    echoBlue "删除recordSet" 1>&2
    local curlInfo curlCode
    curlInfo=$(curl -X "DELETE" -w "Code:%{response_code}" -H "Content-Type: application/json;charset=utf8" -H "X-Auth-Token: ${IAMToken}" "${dnsEndPoint}/v2/zones/${zoneId}/recordsets/${recordSetId}")
    curlCode="$?"
    debug "$curlInfo" 1>&2
    if [ "$curlCode" -ne 0 ]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | tr -d "\n" | sed -e "s/.*Code://g")
        if [ "$responseCode" != "202" ]; then
            echoRed "响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            echoGreen "recordSet删除成功" 1>&2
            return 0
        fi
    fi
}
function AddRecordSet() {
    local zoneId="$1"
    local zone="$2"
    local name="$3"
    local type="$4"
    local record="$5"
    local ttl="$6"
    echoBlue "增加recordSet... " 1>&2
    if [ -z $(echo "$zone" | grep "\.$") ]; then
        zone="${zone}."
    fi
    if [ -z $(echo "$name" | grep "\.$") ]; then
        name="${name}."
    fi
    if [ -z "$type" ]; then
        type="A"
    fi
    if [ -z "$ttl" ]; then
        ttl=${defaultTTL}
    fi
    if [ "$type" == "TXT" ]; then
        record="\\\"${record}\\\""
    fi
    local curlInfo curlCode
    local postBody="{
        \"name\": \"${name}${zone}\",
        \"type\": \"${type}\",
        \"ttl\": ${ttl},
        \"records\": [
            \"${record}\"
        ]
    }"
    debug "$postBody" 1>&2
    curlInfo=$(curl -X "POST" -w "Code:%{response_code}" -H "Content-Type: application/json;charset=utf8" -H "X-Auth-Token: ${IAMToken}" -d "${postBody}" "${dnsEndPoint}/v2/zones/${zoneId}/recordsets")
    curlCode="$?"
    debug "$curlInfo" 1>&2
    if [ "$curlCode" -ne 0 ]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | tr -d "\n" | sed -e "s/.*Code://g")
        if [ "$responseCode" != "202" ]; then
            echoRed "响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            echoGreen "recordSet添加成功" 1>&2
            return 0
        fi
    fi
}
function UpdateRecordSet() {
    local zoneId="$1"
    local recordSetId="$2"
    local record="$3"
    echoBlue "修改recordSet..." 1>&2
    local curlInfo curlCode
    local putBody="{
        \"records\": [
            \"${record}\"
        ]
    }"
    debug "$putBody" 1>&2
    curlInfo=$(curl -X "PUT" -w "Code:%{response_code}" -H "Content-Type: application/json;charset=utf8" -H "X-Auth-Token: ${IAMToken}" -d "${putBody}" "${dnsEndPoint}/v2/zones/${zoneId}/recordsets/${recordSetId}")
    curlCode="$?"
    debug "$curlInfo" 1>&2
    if [ "$curlCode" -ne 0 ]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | tr -d "\n" | sed -e "s/.*Code://g")
        if [ "$responseCode" != "202" ]; then
            echoRed "响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            echoGreen "recordSet修改成功" 1>&2
            return 0
        fi
    fi
}
# HUAWEI API End


function UpdateHost() { # 更新宿主机的地址 输入 recordName device zone name
    local recordName="$1"
    local device="$2"
    local zone="$3"
    local name="$4"
    echoBlue "更新${recordName}" 1>&2
    local ipv4History ipv6History
    ipv4History=$(echo "$history" | grep "^${recordName} " | cut -d " " -f 2)
    ipv6History=$(echo "$history" | grep "^${recordName} " | cut -d " " -f 3)
    if [ -n "$device" ]; then
        device="dev $device"
    fi
    local ipv4Address ipv6Address
    ipv4Address=$(ip -4 addr list scope global $device | sed -n "s/.*inet \([0-9.]\+\).*/\1/p" | head -n 1) #宿主机ipv4
    ipv6Address=$(ip -6 addr list scope global $device | grep -v " fd" | sed -n 's/.*inet6 \([0-9a-f:]\+\).*/\1/p' | head -n 1) #宿主机ipv6

    if [[ -n "$ipv4Address" && "$ipv4History" != "$ipv4Address" ]]; then
        echoBlue "ipv4变更" 1>&2
        debug "记录: ${ipv4History}" 1>&2
        debug "实际: ${ipv4Address}" 1>&2
        if [ -z "${IAMToken}" ]; then
            echoBlue "IAMToken为空" 1>&2
            echoBlue "尝试获取IAMToken" 1>&2
            IAMToken=$(GetIAMToken "${accountName}" "${IAMUserName}" "${IAMUserPassword}")
            debug "IAMToken:${IAMToken}" 1>&2
        fi
        if [ -n "${IAMToken}" ]; then
            if [ -z "$zoneId" ]; then
                local zoneId
                zoneId=$(GetZoneId "$zone")
                debug "zoneId:${zoneId}" 1>&2
            fi
            if [ -n "$zoneId" ]; then
                local recordSetId recordSetIdStatus
                recordSetId=$(GetRecordSetId "$zoneId" "$zone" "$name" "A")
                recordSetIdStatus="$?"
                debug "recordSetId:${recordSetId}" 1>&2
                if [ "$recordSetIdStatus" -eq 1 ]; then
                    echoRed "recordSetId信息查询失败" 1>&2
                elif [ "$recordSetIdStatus" -eq 2 ]; then
                    echoBlue "无记录集，添加..." 1>&2
                    AddRecordSet "$zoneId" "$zone" "$name" "A" "$ipv4Address"
                    if [ "$?" -eq 0 ]; then
                        ipv4History="$ipv4Address"
                    fi
                else
                    local recordsNum=$(echo "$recordSetId" | wc -l)
                    if [ "$recordsNum" -eq 1 ]; then
                        echoBlue "修改现有记录集..." 1>&2
                        UpdateRecordSet "$zoneId" "$recordSetId" "$ipv4Address"
                        if [ "$?" -eq 0 ]; then
                            ipv4History="$ipv4Address"
                        fi
                    else
                        local deleteFail=0
                        echoBlue "有多个记录集，删除多余..." 1>&2
                        for ((i=2; i<="${recordsNum}";i++)); do
                            DeleteRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "${i}p")"
                            if [ "$?" -ne 0 ]; then
                                deleteFail=1
                            fi
                        done
                        if [ "$deleteFail" -eq 0 ]; then
                            echoBlue "修改现有记录集..." 1>&2
                            UpdateRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "1p")" "$ipv4Address"
                            if [ "$?" -eq 0 ]; then
                                ipv4History="$ipv4Address"
                            fi
                        else
                            echoRed "删除失败" 1>&2
                        fi
                    fi
                fi
            else
                echoRed "zoneId获取失败" 1>&2
            fi
        else
            echoRed "IAMToken获取失败" 1>&2
        fi
    fi

    if [[ -n "$ipv6Address" && "$ipv6History" != "$ipv6Address" ]]; then
        echoBlue "ipv6变更" 1>&2
        debug "记录: ${ipv6History}" 1>&2
        debug "实际: ${ipv6Address}" 1>&2
        if [ -z "${IAMToken}" ]; then
            echoBlue "IAMToken为空" 1>&2
            echoBlue "尝试获取IAMToken" 1>&2
            IAMToken=$(GetIAMToken "${accountName}" "${IAMUserName}" "${IAMUserPassword}")
            debug "IAMToken:${IAMToken}" 1>&2
        fi
        if [ -n "${IAMToken}" ]; then
            if [ -z "$zoneId" ]; then
                local zoneId
                zoneId=$(GetZoneId "$zone")
                debug "zoneId:${zoneId}" 1>&2
            fi
            if [ -n "$zoneId" ]; then
                local recordSetId recordSetIdStatus
                recordSetId=$(GetRecordSetId "$zoneId" "$zone" "$name" "AAAA")
                recordSetIdStatus="$?"
                debug "recordSetId:${recordSetId}" 1>&2
                if [ "$recordSetIdStatus" -eq 1 ]; then
                    echoRed "recordSetId信息查询失败" 1>&2
                elif [ "$recordSetIdStatus" -eq 2 ]; then
                    echoBlue "无记录集，添加..." 1>&2
                    AddRecordSet "$zoneId" "$zone" "$name" "AAAA" "$ipv6Address"
                    if [ "$?" -eq 0 ]; then
                        ipv6History="$ipv6Address"
                    fi
                else
                    local recordsNum=$(echo "$recordSetId" | wc -l)
                    if [ "$recordsNum" -eq 1 ]; then
                        echoBlue "修改现有记录集..." 1>&2
                        UpdateRecordSet "$zoneId" "$recordSetId" "$ipv6Address"
                        if [ "$?" -eq 0 ]; then
                            ipv6History="$ipv6Address"
                        fi
                    else
                        local deleteFail=0
                        echoBlue "有多个记录集，删除多余..." 1>&2
                        for ((i=2; i<="${recordsNum}";i++)); do
                            DeleteRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "${i}p")"
                            if [ "$?" -ne 0 ]; then
                                deleteFail=1
                            fi
                        done
                        if [ "$deleteFail" -eq 0 ]; then
                            echoBlue "修改现有记录集..." 1>&2
                            UpdateRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "1p")" "$ipv6Address"
                            if [ "$?" -eq 0 ]; then
                                ipv6History="$ipv6Address"
                            fi
                        else
                            echoRed "删除失败" 1>&2
                        fi
                    fi
                fi
            else
                echoRed "zoneId获取失败" 1>&2
            fi
        else
            echoRed "IAMToken获取失败" 1>&2
        fi
    fi

    echo "${recordName} ${ipv4History} ${ipv6History}"
}

function UpdateHostIPv4() { # 更新宿主机的地址 ipv4 Only 输入 recordName device zone name
    local recordName="$1"
    local device="$2"
    local zone="$3"
    local name="$4"
    echoBlue "更新${recordName} IPv4Only" 1>&2
    local ipv4History ipv6History
    ipv4History=$(echo "$history" | grep "^${recordName} " | cut -d " " -f 2)
    if [ -n "$device" ]; then
        device="dev $device"
    fi
    local ipv4Address ipv6Address
    ipv4Address=$(ip -4 addr list scope global $device | sed -n "s/.*inet \([0-9.]\+\).*/\1/p" | head -n 1)

    if [[ -n "$ipv4Address" && "$ipv4History" != "$ipv4Address" ]]; then
        echoBlue "ipv4变更" 1>&2
        debug "记录: ${ipv4History}" 1>&2
        debug "实际: ${ipv4Address}" 1>&2
        if [ -z "${IAMToken}" ]; then
            echoBlue "IAMToken为空" 1>&2
            echoBlue "尝试获取IAMToken" 1>&2
            IAMToken=$(GetIAMToken "${accountName}" "${IAMUserName}" "${IAMUserPassword}")
            debug "IAMToken:${IAMToken}" 1>&2
        fi
        if [ -n "${IAMToken}" ]; then
            if [ -z "$zoneId" ]; then
                local zoneId
                zoneId=$(GetZoneId "$zone")
                debug "zoneId:${zoneId}" 1>&2
            fi
            if [ -n "$zoneId" ]; then
                local recordSetId recordSetIdStatus
                recordSetId=$(GetRecordSetId "$zoneId" "$zone" "$name" "A")
                recordSetIdStatus="$?"
                debug "recordSetId:${recordSetId}" 1>&2
                if [ "$recordSetIdStatus" -eq 1 ]; then
                    echoRed "recordSetId信息查询失败" 1>&2
                elif [ "$recordSetIdStatus" -eq 2 ]; then 
                    echoBlue "无记录集，添加..." 1>&2
                    AddRecordSet "$zoneId" "$zone" "$name" "A" "$ipv4Address"
                    if [ "$?" -eq 0 ]; then
                        ipv4History="$ipv4Address"
                    fi
                else
                    local recordsNum=$(echo "$recordSetId" | wc -l)
                    if [ "$recordsNum" -eq 1 ]; then
                        echoBlue "修改现有记录集..." 1>&2
                        UpdateRecordSet "$zoneId" "$recordSetId" "$ipv4Address"
                        if [ "$?" -eq 0 ]; then
                            ipv4History="$ipv4Address"
                        fi
                    else
                        local deleteFail=0
                        echoBlue "有多个记录集，删除多余..." 1>&2
                        for ((i=2; i<="${recordsNum}";i++)); do
                            DeleteRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "${i}p")"
                            if [ "$?" -ne 0 ]; then
                                deleteFail=1
                            fi
                        done
                        if [ "$deleteFail" -eq 0 ]; then
                            echoBlue "修改现有记录集..." 1>&2
                            UpdateRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "1p")" "$ipv4Address"
                            if [ "$?" -eq 0 ]; then
                                ipv4History="$ipv4Address"
                            fi
                        else
                            echoRed "删除失败" 1>&2
                        fi
                    fi
                fi
            else
                echoRed "zoneId获取失败" 1>&2
            fi
        else
            echoRed "IAMToken获取失败" 1>&2
        fi
    fi

    echo "${recordName} ${ipv4History} ${ipv6History}"
}

function UpdateHostIPv6() { # 更新宿主机的地址 ipv6 Only 输入 recordName device zone name
    local recordName="$1"
    local device="$2"
    local zone="$3"
    local name="$4"
    echoBlue "更新${recordName} IPv6Only" 1>&2
    local ipv4History ipv6History

    ipv6History=$(echo "$history" | grep "^${recordName} " | cut -d " " -f 3)
    if [ -n "$device" ]; then
        device="dev $device"
    fi
    local ipv4Address ipv6Address

    ipv6Address=$(ip -6 addr list scope global $device | grep -v " fd" | sed -n 's/.*inet6 \([0-9a-f:]\+\).*/\1/p' | head -n 1)

    if [[ -n "$ipv6Address" && "$ipv6History" != "$ipv6Address" ]]; then
        echoBlue "ipv6变更" 1>&2
        debug "记录: ${ipv6History}" 1>&2
        debug "实际: ${ipv6Address}" 1>&2
        if [ -z "${IAMToken}" ]; then
            echoBlue "IAMToken为空" 1>&2
            echoBlue "尝试获取IAMToken" 1>&2
            IAMToken=$(GetIAMToken "${accountName}" "${IAMUserName}" "${IAMUserPassword}")
            debug "IAMToken:${IAMToken}" 1>&2
        fi
        if [ -n "${IAMToken}" ]; then
            if [ -z "$zoneId" ]; then
                local zoneId
                zoneId=$(GetZoneId "$zone")
                debug "zoneId:${zoneId}" 1>&2
            fi
            if [ -n "$zoneId" ]; then
                local recordSetId recordSetIdStatus
                recordSetId=$(GetRecordSetId "$zoneId" "$zone" "$name" "AAAA")
                recordSetIdStatus="$?"
                debug "recordSetId:${recordSetId}" 1>&2
                if [ "$recordSetIdStatus" -eq 1 ]; then
                    echoRed "recordSetId信息查询失败" 1>&2
                elif [ "$recordSetIdStatus" -eq 2 ]; then
                    echoBlue "无记录集，添加..." 1>&2
                    AddRecordSet "$zoneId" "$zone" "$name" "AAAA" "$ipv6Address"
                    if [ "$?" -eq 0 ]; then
                        ipv6History="$ipv6Address"
                    fi
                else
                    local recordsNum=$(echo "$recordSetId" | wc -l)
                    if [ "$recordsNum" -eq 1 ]; then
                        echoBlue "修改现有记录集..." 1>&2
                        UpdateRecordSet "$zoneId" "$recordSetId" "$ipv6Address"
                        if [ "$?" -eq 0 ]; then
                            ipv6History="$ipv6Address"
                        fi
                    else
                        local deleteFail=0
                        echoBlue "有多个记录集，删除多余..." 1>&2
                        for ((i=2; i<="${recordsNum}";i++)); do
                            DeleteRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "${i}p")"
                            if [ "$?" -ne 0 ]; then
                                deleteFail=1
                            fi
                        done
                        if [ "$deleteFail" -eq 0 ]; then
                            echoBlue "修改现有记录集..." 1>&2
                            UpdateRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "1p")" "$ipv6Address"
                            if [ "$?" -eq 0 ]; then
                                ipv6History="$ipv6Address"
                            fi
                        else
                            echoRed "删除失败" 1>&2
                        fi
                    fi
                fi
            else
                echoRed "zoneId获取失败" 1>&2
            fi
        else
            echoRed "IAMToken获取失败" 1>&2
        fi
    fi

    echo "${recordName} ${ipv4History} ${ipv6History}"
}

function UpdateContainer() { # 更新容器的地址 输入 recordName containerName device zone name
    local recordName="$1"
    local containerName="$2"
    local device="$3"
    local zone="$4"
    local name="$5"
    echoBlue "更新${recordName}" 1>&2
    local ipv4History ipv6History
    ipv4History=$(echo "$history" | grep "^${recordName} " | cut -d " " -f 2)
    ipv6History=$(echo "$history" | grep "^${recordName} " | cut -d " " -f 3)
    if [ -n "$device" ]; then
        device="dev $device"
    fi
    local ipv4Address ipv6Address
    ipv4Address=$(lxc exec local:${containerName} -- ip -4 addr list scope global $device | sed -n "s/.*inet \([0-9.]\+\).*/\1/p" | head -n 1)
    ipv6Address=$(lxc exec local:${containerName} -- ip -6 addr list scope global $device | grep -v " fd" | sed -n 's/.*inet6 \([0-9a-f:]\+\).*/\1/p' | head -n 1)

    if [[ -n "$ipv4Address" && "$ipv4History" != "$ipv4Address" ]]; then
        echoBlue "ipv4变更" 1>&2
        debug "记录: ${ipv4History}" 1>&2
        debug "实际: ${ipv4Address}" 1>&2
        if [ -z "${IAMToken}" ]; then
            echoBlue "IAMToken为空" 1>&2
            echoBlue "尝试获取IAMToken" 1>&2
            IAMToken=$(GetIAMToken "${accountName}" "${IAMUserName}" "${IAMUserPassword}")
            debug "IAMToken:${IAMToken}" 1>&2
        fi
        if [ -n "${IAMToken}" ]; then
            if [ -z "$zoneId" ]; then
                local zoneId
                zoneId=$(GetZoneId "$zone")
                debug "zoneId:${zoneId}" 1>&2
            fi
            if [ -n "$zoneId" ]; then
                local recordSetId recordSetIdStatus
                recordSetId=$(GetRecordSetId "$zoneId" "$zone" "$name" "A")
                recordSetIdStatus="$?"
                debug "recordSetId:${recordSetId}" 1>&2
                if [ "$recordSetIdStatus" -eq 1 ]; then
                    echoRed "recordSetId信息查询失败" 1>&2
                elif [ "$recordSetIdStatus" -eq 2 ]; then
                    echoBlue "无记录集，添加..." 1>&2
                    AddRecordSet "$zoneId" "$zone" "$name" "A" "$ipv4Address"
                    if [ "$?" -eq 0 ]; then
                        ipv4History="$ipv4Address"
                    fi
                else
                    local recordsNum=$(echo "$recordSetId" | wc -l)
                    if [ "$recordsNum" -eq 1 ]; then
                        echoBlue "修改现有记录集..." 1>&2
                        UpdateRecordSet "$zoneId" "$recordSetId" "$ipv4Address"
                        if [ "$?" -eq 0 ]; then
                            ipv4History="$ipv4Address"
                        fi
                    else
                        local deleteFail=0
                        echoBlue "有多个记录集，删除多余..." 1>&2
                        for ((i=2; i<="${recordsNum}";i++)); do
                            DeleteRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "${i}p")"
                            if [ "$?" -ne 0 ]; then
                                deleteFail=1
                            fi
                        done
                        if [ "$deleteFail" -eq 0 ]; then
                            echoBlue "修改现有记录集..." 1>&2
                            UpdateRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "1p")" "$ipv4Address"
                            if [ "$?" -eq 0 ]; then
                                ipv4History="$ipv4Address"
                            fi
                        else
                            echoRed "删除失败" 1>&2
                        fi
                    fi
                fi
            else
                echoRed "zoneId获取失败" 1>&2
            fi
        else
            echoRed "IAMToken获取失败" 1>&2
        fi
    fi

    if [[ -n "$ipv6Address" && "$ipv6History" != "$ipv6Address" ]]; then
        echoBlue "ipv6变更" 1>&2
        debug "记录: ${ipv6History}" 1>&2
        debug "实际: ${ipv6Address}" 1>&2
        if [ -z "${IAMToken}" ]; then
            echoBlue "IAMToken为空" 1>&2
            echoBlue "尝试获取IAMToken" 1>&2
            IAMToken=$(GetIAMToken "${accountName}" "${IAMUserName}" "${IAMUserPassword}")
            debug "IAMToken:${IAMToken}" 1>&2
        fi
        if [ -n "${IAMToken}" ]; then
            if [ -z "$zoneId" ]; then
                local zoneId
                zoneId=$(GetZoneId "$zone")
                debug "zoneId:${zoneId}" 1>&2
            fi
            if [ -n "$zoneId" ]; then
                local recordSetId recordSetIdStatus
                recordSetId=$(GetRecordSetId "$zoneId" "$zone" "$name" "AAAA")
                recordSetIdStatus="$?"
                debug "recordSetId:${recordSetId}" 1>&2
                if [ "$recordSetIdStatus" -eq 1 ]; then
                    echoRed "recordSetId信息查询失败" 1>&2
                elif [ "$recordSetIdStatus" -eq 2 ]; then
                    echoBlue "无记录集，添加..." 1>&2
                    AddRecordSet "$zoneId" "$zone" "$name" "AAAA" "$ipv6Address"
                    if [ "$?" -eq 0 ]; then
                        ipv6History="$ipv6Address"
                    fi
                else
                    local recordsNum=$(echo "$recordSetId" | wc -l)
                    if [ "$recordsNum" -eq 1 ]; then
                        echoBlue "修改现有记录集..." 1>&2
                        UpdateRecordSet "$zoneId" "$recordSetId" "$ipv6Address"
                        if [ "$?" -eq 0 ]; then
                            ipv6History="$ipv6Address"
                        fi
                    else
                        local deleteFail=0
                        echoBlue "有多个记录集，删除多余..." 1>&2
                        for ((i=2; i<="${recordsNum}";i++)); do
                            DeleteRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "${i}p")"
                            if [ "$?" -ne 0 ]; then
                                deleteFail=1
                            fi
                        done
                        if [ "$deleteFail" -eq 0 ]; then
                            echoBlue "修改现有记录集..." 1>&2
                            UpdateRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "1p")" "$ipv6Address"
                            if [ "$?" -eq 0 ]; then
                                ipv6History="$ipv6Address"
                            fi
                        else
                            echoRed "删除失败" 1>&2
                        fi
                    fi
                fi
            else
                echoRed "zoneId获取失败" 1>&2
            fi
        else
            echoRed "IAMToken获取失败" 1>&2
        fi
    fi

    echo "${recordName} ${ipv4History} ${ipv6History}"
}

function UpdateContainerIPv4() { # 更新容器的地址 ipv4 Only 输入 recordName containerName device zone name
    local recordName="$1"
    local containerName="$2"
    local device="$3"
    local zone="$4"
    local name="$5"
    echoBlue "更新${recordName} IPv4Only" 1>&2
    local ipv4History ipv6History
    ipv4History=$(echo "$history" | grep "^${recordName} " | cut -d " " -f 2)

    if [ -n "$device" ]; then
        device="dev $device"
    fi
    local ipv4Address ipv6Address
    ipv4Address=$(lxc exec local:${containerName} -- ip -4 addr list scope global $device | sed -n "s/.*inet \([0-9.]\+\).*/\1/p" | head -n 1)

    if [[ -n "$ipv4Address" && "$ipv4History" != "$ipv4Address" ]]; then
        echoBlue "ipv4变更" 1>&2
        debug "记录: ${ipv4History}" 1>&2
        debug "实际: ${ipv4Address}" 1>&2
        if [ -z "${IAMToken}" ]; then
            echoBlue "IAMToken为空" 1>&2
            echoBlue "尝试获取IAMToken" 1>&2
            IAMToken=$(GetIAMToken "${accountName}" "${IAMUserName}" "${IAMUserPassword}")
            debug "IAMToken:${IAMToken}" 1>&2
        fi
        if [ -n "${IAMToken}" ]; then
            if [ -z "$zoneId" ]; then
                local zoneId
                zoneId=$(GetZoneId "$zone")
                debug "zoneId:${zoneId}" 1>&2
            fi
            if [ -n "$zoneId" ]; then
                local recordSetId recordSetIdStatus
                recordSetId=$(GetRecordSetId "$zoneId" "$zone" "$name" "A")
                recordSetIdStatus="$?"
                debug "recordSetId:${recordSetId}" 1>&2
                if [ "$recordSetIdStatus" -eq 1 ]; then
                    echoRed "recordSetId信息查询失败" 1>&2
                elif [ "$recordSetIdStatus" -eq 2 ]; then
                    echoBlue "无记录集，添加..." 1>&2
                    AddRecordSet "$zoneId" "$zone" "$name" "A" "$ipv4Address"
                    if [ "$?" -eq 0 ]; then
                        ipv4History="$ipv4Address"
                    fi
                else
                    local recordsNum=$(echo "$recordSetId" | wc -l)
                    if [ "$recordsNum" -eq 1 ]; then
                        echoBlue "修改现有记录集..." 1>&2
                        UpdateRecordSet "$zoneId" "$recordSetId" "$ipv4Address"
                        if [ "$?" -eq 0 ]; then
                            ipv4History="$ipv4Address"
                        fi
                    else
                        local deleteFail=0
                        echoBlue "有多个记录集，删除多余..." 1>&2
                        for ((i=2; i<="${recordsNum}";i++)); do
                            DeleteRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "${i}p")"
                            if [ "$?" -ne 0 ]; then
                                deleteFail=1
                            fi
                        done
                        if [ "$deleteFail" -eq 0 ]; then
                            echoBlue "修改现有记录集..." 1>&2
                            UpdateRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "1p")" "$ipv4Address"
                            if [ "$?" -eq 0 ]; then
                                ipv4History="$ipv4Address"
                            fi
                        else
                            echoRed "删除失败" 1>&2
                        fi
                    fi
                fi
            else
                echoRed "zoneId获取失败" 1>&2
            fi
        else
            echoRed "IAMToken获取失败" 1>&2
        fi
    fi

    echo "${recordName} ${ipv4History} ${ipv6History}"
}

function UpdateContainerIPv6() { # 更新容器的地址 ipv6 Only 输入 recordName containerName device zone name
    local recordName="$1"
    local containerName="$2"
    local device="$3"
    local zone="$4"
    local name="$5"
    echoBlue "更新${recordName} IPv6Only" 1>&2
    local ipv4History ipv6History

    ipv6History=$(echo "$history" | grep "^${recordName} " | cut -d " " -f 3)
    if [ -n "$device" ]; then
        device="dev $device"
    fi
    local ipv4Address ipv6Address

    ipv6Address=$(lxc exec local:${containerName} -- ip -6 addr list scope global $device | grep -v " fd" | sed -n 's/.*inet6 \([0-9a-f:]\+\).*/\1/p' | head -n 1)

    if [[ -n "$ipv6Address" && "$ipv6History" != "$ipv6Address" ]]; then
        echoBlue "ipv6变更" 1>&2
        debug "记录: ${ipv6History}" 1>&2
        debug "实际: ${ipv6Address}" 1>&2
        if [ -z "${IAMToken}" ]; then
            echoBlue "IAMToken为空" 1>&2
            echoBlue "尝试获取IAMToken" 1>&2
            IAMToken=$(GetIAMToken "${accountName}" "${IAMUserName}" "${IAMUserPassword}")
            debug "IAMToken:${IAMToken}" 1>&2
        fi
        if [ -n "${IAMToken}" ]; then
            if [ -z "$zoneId" ]; then
                local zoneId
                zoneId=$(GetZoneId "$zone")
                debug "zoneId:${zoneId}" 1>&2
            fi
            if [ -n "$zoneId" ]; then
                local recordSetId recordSetIdStatus
                recordSetId=$(GetRecordSetId "$zoneId" "$zone" "$name" "AAAA")
                recordSetIdStatus="$?"
                debug "recordSetId:${recordSetId}" 1>&2
                if [ "$recordSetIdStatus" -eq 1 ]; then
                    echoRed "recordSetId信息查询失败" 1>&2
                elif [ "$recordSetIdStatus" -eq 2 ]; then
                    echoBlue "无记录集，添加..." 1>&2
                    AddRecordSet "$zoneId" "$zone" "$name" "AAAA" "$ipv6Address"
                    if [ "$?" -eq 0 ]; then
                        ipv6History="$ipv6Address"
                    fi
                else
                    local recordsNum=$(echo "$recordSetId" | wc -l)
                    if [ "$recordsNum" -eq 1 ]; then
                        echoBlue "修改现有记录集..." 1>&2
                        UpdateRecordSet "$zoneId" "$recordSetId" "$ipv6Address"
                        if [ "$?" -eq 0 ]; then
                            ipv6History="$ipv6Address"
                        fi
                    else
                        local deleteFail=0
                        echoBlue "有多个记录集，删除多余..." 1>&2
                        for ((i=2; i<="${recordsNum}";i++)); do
                            DeleteRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "${i}p")"
                            if [ "$?" -ne 0 ]; then
                                deleteFail=1
                            fi
                        done
                        if [ "$deleteFail" -eq 0 ]; then
                            echoBlue "修改现有记录集..." 1>&2
                            UpdateRecordSet "$zoneId" "$(echo "$recordSetId" | sed -n -e "1p")" "$ipv6Address"
                            if [ "$?" -eq 0 ]; then
                                ipv6History="$ipv6Address"
                            fi
                        else
                            echoRed "删除失败" 1>&2
                        fi
                    fi
                fi
            else
                echoRed "zoneId获取失败" 1>&2
            fi
        else
            echoRed "IAMToken获取失败" 1>&2
        fi
    fi

    echo "${recordName} ${ipv4History} ${ipv6History}"
}



if [ -r "$historyFile" ]; then
    history=$(cat "$historyFile")
fi
debug "History:" 1>&2
debug "${history}" 1>&2

{
    UpdateHostIPv4 Master-1 eth0 "example.org" "example"
    UpdateHostIPv6 Master-2 eth0 "example.com" "example"
    UpdateContainer Container-1 Container-1 eth0 "example.org" "example"
} > "$historyFile"

debug "Update:" 1>&2
debug "$(cat "$historyFile")" 1>&2
