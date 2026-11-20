#!/usr/bin/env bash

MOJANG_MANIFEST="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
PAPMC_PROJECTS="https://fill.papermc.io/v3/projects"

FABMC_LOADERS="https://meta.fabricmc.net/v2/versions/loader"
FABMC_INSTALLERS="https://meta.fabricmc.net/v2/versions/installer"


# Where to download which server software
declare -A SOFT_VERSIONS=(
    [vanilla]="mojang"
    [paper]="papermc"
    [folia]="papermc"
    [velocity]="papermc"
    [fabric]="fabricmc"
)

result=

# Allow to download non stable versions
nonStable=false

function printHelp()
{
    echo -e "\
Usage: ./server.sh [OPTION]...
Download minecraft server software.

Examples:
    ./server.sh -v 26.1 -o vanilla-26.1.jar                     # Download a 26.1 minecraft vanilla server and save it to ./vanilla-26.1.jar
    ./server.sh -v 1.18 -s paper -o paper1.18.jar               # Download a 1.18 papermc server and save it to ./paper1.18.jar
    ./server.sh -v 26.2 -s fabric --software-version 0.20.1     # Download a 26.2 fabric server with fabric version 0.20.1
    ./server.sh -v 1.8 -o pvpserver.jar                         # Download a 1.8 vanilla server and save it to ./pvpserver.jar

Options:
    -h, --help                                      Show this help menu
    -o, --out <file>                                Set file to download to
    -v, --version <version>                         Specify the minecraft version
    -s, --software <software>                       Set server software eg. vanilla, paper, fabric etc.
    --software-version <version>                    Set a specific software version eg. for paper
    --allow-unstable                                Allow unstable server eg. paper versions to be used
    "
}


function assert()
{
	if ! eval $1; then
		echo "Assertion failed: $1"
		exit 1
	fi
}

function check_cmd()
{
	assert "[ ! -z ${1+x} ]"

	if ! which $1 >/dev/null 2>&1; then
		echo "Please install required command: '${1}'"
        exit 2
	fi
}


# $1 : Minecraft version (required)
# $2 : Fabric server version (empty for latest)
# $3 : Allow non-stable fabric versions
# result : (downl-url, "", "none")
function getDownloadLinkFabricmc()
{
    assert "[ ! -z $1 ]"
    local mcver="$1"
    local softver="$2"
    local allowUnst="$3"

    local response=$(curl -s -X 'GET' "${FABMC_LOADERS}/${mcver}" -H 'accept: application/json' 2>/dev/null)

    if [[ -z $response ]]; then
        echo 'API request failed! Response is empty'
        echo 'Does this version of fabric exist?'
        exit 1
    fi


    local loadver=
    if [[ -z $softver ]]; then
        if ! $allowUnst; then
            # Search for first stable release
            loadver=$(jq -r '[.[] | select(.loader.stable == true)][0] | .loader.version' <<< $response)
        else
            # Just use first release
            loadver=$(jq -r '.[0].loader.version' <<< $response)
        fi

        if [[ -z $loadver ]] || [[ $loadver == "null" ]]; then
            echo "Could not find any paper ${mcver} versions"
            echo 'Maybe try "--allow-unstable" if not done already'
            exit 1
        fi
    else
        # I know a bit weird but also a check if this really exists
        local verStruct=$(jq -r '.[] | select(.loader.version == "'$softver'")' <<< $response)
        loadver=$(jq '.loader.version' <<< $verStruct)

        if [[ -z $loadver ]] || [[ $loadver == "null" ]]; then
            echo "Could not find any fabric ${mcver} version ${softver} versions"
            exit 1
        fi

        # Stable check
        if ! $allowUnst; then
            local stable=$(jq -r '.loader.stable' <<< $verStruct)

            if [[ $stable -ne 'true' ]]; then
                echo "Could not find stable version of ${soft} ${mcver} version ${softver}"
                echo 'Maybe try "--allow-unstable" if not done already'
                exit 1
            fi
        fi
        #
    fi

    response=$(curl -s -X 'GET' "${FABMC_INSTALLERS}" -H 'accept: application/json' 2>/dev/null)

    # Get latest stable installer version
    local instver=$(jq -r '[.[] | select(.stable == true)][0] | .version' <<< $response)

    result=("${FABMC_LOADERS}/${mcver}/${loadver}/${instver}/server/jar" "" "none")
}


# $1 : Minecraft version (required)
# $2 : Papermc server software (required)
# $3 : Server software version (empty for latest)
# $4 : Allow non-stable server softwares
# result : (downl-url, hash, "sha256")
function getDownloadLinkPapermc()
{
    assert "[ ! -z $1 ]"
    assert "[ ! -z $2 ]"
    local mcver="$1"
    local soft="$2"
    local softver="$3"
    local allowUnst="$4"

    local response=$(curl -s -X 'GET' "${PAPMC_PROJECTS}/${soft}/versions/${mcver}/builds" -H 'accept: application/json' 2>/dev/null)

    if [[ -z $response ]] || [[ $response == "null" ]]; then
        echo 'API request failed! Response is empty'
        echo 'Does this software & version exist?'
        exit 1
    fi

    if [[ -z $softver ]]; then
        if ! $allowUnst; then
            # Search for first stable release
            response=$(jq '[.[] | select(.channel == "STABLE")][0]' <<< $response)
        else
            # Just use first release
            response=$(jq '.[0]' <<< $response)
        fi

        if [[ -z $response ]] || [[ $response == "null" ]]; then
            echo "Could not find any ${soft} ${mcver} version"
            echo 'Maybe try "--allow-unstable" if not done already'
            exit 1
        fi
    else
        response=$(jq '.[] | select(.id == "$softver")' <<< $response)

        if [[ -z $response ]] || [[ $response == "null" ]]; then
            echo "Could not find any ${soft} ${mcver} version ${softver} versions"
            exit 1
        fi

        # Stable check
        if ! $allowUnst; then
            local channel=$(jq -r '.channel' <<< $response)

            if [[ $channel -ne "STABLE" ]]; then
                echo "Could not find stable version of ${soft} ${mcver} version ${softver}"
                echo 'Maybe try "--allow-unstable" if not done already'
                exit 1
            fi
        fi
        #
    fi

    local infoStruct=$(jq '.downloads.["server:default"]' <<< $response)
    local downlUrl=$(jq -r '.url' <<< $infoStruct)
    local fileHash=$(jq -r '.checksums.sha256' <<< $infoStruct)

    result=($downlUrl $fileHash 'sha256')
}

# $1 : Minecraft version (required)
# result : (down-url, hash, "sha1")
function getDownloadLinkMojang()
{
    assert "[ ! -z $1 ]"
    local mcver="$1"

    local response=$(curl -s -X 'GET' "$MOJANG_MANIFEST" -H 'accept: application/json' 2>/dev/null)

    if [[ -z $response ]]; then
        echo 'API request failed! Response is empty'
        echo 'Does this version exist?'
        exit 1
    fi

    local infoStructUrl=$(jq -r '.versions.[] | select(.id=="'$mcver'") | .url' <<< $response)
    local infoStruct=$(curl -s -X 'GET' "$infoStructUrl" -H 'accept: application/json' 2>/dev/null)

    if [[ -z $infoStruct ]]; then
        echo 'API request failed! Response is empty'
        exit 1
    fi

    local downUrl=$(jq -r '.downloads.server.url' <<< $infoStruct)
    local fileHash=$(jq -r '.downloads.server.sha1' <<< $infoStruct)

    result=($downUrl $fileHash "sha1")
}

# $1 : Minecraft version (required)
# $2 : Server software (vanilla, paper) (default: vanilla)
# $3 : Server software version (default: newest)
# $4 : Allow non-stable server softwares
# result : (down-url, file-hash, hash-type(sha256, sha1))
function getDownloadLink()
{
    assert "[ ! -z $1 ]"
    local mcver="$1"
    local soft="$2"
    local softver="$3"
    local allowUnst="$4"

    if [[ -z $soft ]]; then
        soft="vanilla"
    fi

    if [[ ! -z $softver ]] && [[ $soft == "vanilla" ]]; then
        echo "Using vanilla server software, ignoring manually set software version!"
    fi

    # Empty means newest
    if [[ $softver == "newest" ]]; then
        softver=
    fi

    if [[ -z $allowUnst ]]; then
        allowUnst=false
    fi


    local source=${SOFT_VERSIONS[$soft]}
    if [[ -z $source ]]; then
        echo "Server software '$soft' not supported!"
        exit 1
    fi

    case $source in
        mojang)
            getDownloadLinkMojang "$mcver"
            ;;

        papermc)
            getDownloadLinkPapermc "$mcver" "$soft" "$softver" "$allowUnst"
            ;;

        fabricmc)
            getDownloadLinkFabricmc "$mcver" "$softver" "$allowUnst"
            ;;
    esac
}

# $1 : Minecraft version (required)
# $2 : Server software (vanilla, paper) (default: vanilla)
# $3 : Server software version (default: newest)
# $4 : Allow non-stable server softwares
# $5 : Output file (default: server.jar)
function downloadServer()
{
    assert "[ ! -z $1 ]"
    local mcver="$1"
    local soft="$2"
    local softver="$3"
    local allowUnst="$4"
    local ofile="$5"


    if [[ -z $ofile ]]; then
        ofile="server.jar"
    fi

    getDownloadLink "$mcver" "$soft" "$softver" "$allowUnst"
    local url=${result[0]}
    local hash=${result[1]}
    local shaAlgo=${result[2]}

    echo "Starting download ($url)..."
    curl -sS $url -o $ofile

    if [[ ! -f $ofile ]]; then
        echo "Failed to download file"
        exit 1
    fi

    echo "Checking hash..."

    case $shaAlgo in
        sha1)
            echo "$hash $ofile" | sha1sum --check --status
            ;;

        sha256)
            echo "$hash $ofile" | sha256sum --check --status
            ;;

        none)
            echo "No hash provided, skipping"
            ;;

        *)
            echo "Unknown HASH algo"
            exit 1
            ;;
    esac

    if [[ $? -ne 0 ]]; then
        echo "Hash value check failed! File seems corrupted!"
        exit 1
    fi

    echo "Finished sucessfully"
}


if [[ $# -eq 0 ]]; then
    printHelp
    exit 0
fi

# Check required commands at startup
check_cmd jq
check_cmd curl
check_cmd sha256sum
check_cmd sha1sum


outFile=""
mcVersion=""
software=""
softVersion=""
nonStable=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|'-?'|--help)
            printHelp
            exit 0
            ;;

        -o|--out)
            outFile=$2
            shift 2
            ;;

        -v|--version)
            mcVersion=$2
            shift 2
            ;;

        -s|--software)
            software=$2
            shift 2
            ;;

        --software-version)
            softVersion=$2
            shift 2
            ;;

        --allow-unstable)
            nonStable=true
            shift
            ;;

        *)
            echo "Unknown argument $1"
            printHelp
            exit 1
    esac
done

if [[ -z $mcVersion ]]; then
    echo 'Minecraft version not set. Please use -v, --version to provide the target version'
    exit 1
fi

downloadServer "$mcVersion" "$software" "$softVersion" "$nonStable" "$outFile"

