#!/bin/bash

declare -A error_code=(
    ["install_deps"]=10
    ["ensure_shard"]=11
    ["get_core.download"]=12
    ["get_core.unzip_nightly"]=13
    ["get_core.find_release"]=14
    ["get_core.parse_release"]=15
    ["get_core.unzip_release"]=16
    ["get_distro.download"]=17
    ["get_distro.unzip"]=18
    ["get_distro.merge"]=19
    ["update_core_cfgs"]=20
    ["ecompile"]=21
    ["run_uoconvert.no_maps"]=22
    ["run_uoconvert.create_realmdir"]=23
    ["run_uoconvert.convert_cmd"]=24
    ["run_uoconvert.move_convert"]=25
)

set -e

UODATADIR=${POLSERVER_UODATADIR:-"/MUL"}
SHARDDIR=${POLSERVER_SHARDDIR:-"/Shard"}
REALMDIR=${POLSERVER_REALMDIR:-"/Realm"}
DISTROZIP=${POLSERVER_DISTROZIP:-"https://github.com/polserver/ModernDistro/archive/master.zip"}
COREZIP=${POLSERVER_COREZIP:-"https://github.com/polserver/polserver/releases/download/NightlyRelease/Nightly-Linux-gcc.zip"}

unzip-strip() (
    local zip=$1
    local dest=${2:-.}
    local temp=$(mktemp -d) && unzip -nd "$temp" "$zip" && mkdir -p "$dest" &&
        shopt -s dotglob && local f=("$temp"/*) &&
        if ((${#f[@]} == 1)) && [[ -d "${f[0]}" ]]; then
            mv "$temp"/*/* "$dest"
        else
            mv "$temp"/* "$dest"
        fi && rmdir "$temp"/* "$temp"
)

function install_deps() {
    if ! command -v curl &>/dev/null; then
        (
            apt-get update &&
                apt-get install -y curl unzip libatomic1 mysql-common &&
                curl -o /tmp/libmysqlclient20_5.7.26-1+b1_amd64.deb http://ftp.br.debian.org/debian/pool/main/m/mysql-5.7/libmysqlclient20_5.7.26-1+b1_amd64.deb &&
                dpkg -i /tmp/libmysqlclient20_5.7.26-1+b1_amd64.deb
        ) || (echo "Could not install dependencies" && exit ${error_code[install_deps]})
    fi
}

function ensure_shard() {
    mkdir -p $SHARDDIR $SHARDDIR/data || (echo "Could not create shard directory $SHARDDIR" && exit ${error_code[ensure_shard]})
}

function get_core() {

    if [ -f $SHARDDIR/pol ]; then
        echo "File 'pol' already exists in $SHARDDIR. Skip fetching core..."
        return
    fi

    echo "Downloading $COREZIP"
    local zipbase=$(basename $COREZIP)

    if [ -f $zipbase ]; then
        echo "File already exists: $(readlink -f $zipbase)"
    else
        curl -L -O -N $COREZIP || (echo "Could not download $COREZIP" && exit ${error_code[get_core.download]})
    fi

    unzip -n Nightly-Linux-gcc.zip || (echo "Unzip nightly failed" && exit ${error_code[get_core.unzip_nightly]})

    ZIPFILES=$(find . -maxdepth 1 -name 'polserver*.zip' -and -not -name '*_dbg.zip')

    if [ "$ZIPFILES" == "" ]; then
        echo "Could not find polserver*.dbg,!polserver*_dbg.zip" && exit ${error_code[get_core.find_release]}
    fi

    POLRELEASE=$(echo $ZIPFILES | sed 's/.\/\(.*\).zip/\1/; t; q68')
    if [ $? -eq 68 ]; then
        echo "Could not find POLRELEASE from $ZIPFILES" && exit ${error_code[get_core.parse_release]}
    fi

    echo "Unzipping release $POLRELEASE.zip"

    unzip-strip $POLRELEASE.zip $SHARDDIR || (echo "Unzip release failed" && exit ${error_code[get_core.unzip_release]})

    rm -rf Nightly-Linux-gcc.zip $POLRELEASE.zip ${POLRELEASE}_dbg.zip
}

function update_core_cfgs() {

    # local size=3188736 # hsa
    # local size=1036288 # not hsa
    local size=$(stat -c%s "$UODATADIR/tiledata.mul" 2>/dev/null)
    if [ "$size" == "" ]; then
        echo "Could not find tiledata.mul size" && exit ${error_code[update_core_cfgs]}
    fi

    local nblocks
    local isHSA

    if [ $((($size - 428032) % 1188)) -ne 0 ] && [ $((($size - 493568) % 1316)) -eq 0 ]; then
        isHSA=1
        nblocks=$((($size - 493568) / 1316))
    else
        isHSA=0
        nblocks=$((($size - 428032) / 1188))
    fi

    local maxTileID=$(printf "0x%x" $((32 * $nblocks - 1)))

    (
        pushd $SHARDDIR >/dev/null &&
            sed 's@\(UoDataFileRoot=\).*@\1'"${UODATADIR}"'@g; s@#\(RealmDataPath=\).*@\1'"${REALMDIR}"'@g; s@\(MaxTileID=\).*@\1'$maxTileID'@Ig;' pol.cfg.example >pol.cfg &&
            sed -i "s@\(UseNewHSAFormat\s*\).*@\1$isHSA@Ig;" uoconvert.cfg &&
            pushd scripts >/dev/null &&
            sed 's@\(ModuleDirectory=\).*@\1'"${SHARDDIR}"'/scripts/modules@g; s@\(IncludeDirectory=\).*@\1'"${SHARDDIR}"'/scripts@g; s@\(PolScriptRoot=\).*@\1'"${SHARDDIR}"'/scripts@g; s@\(PackageRoot=\).*@\1'"${SHARDDIR}"'/pkg@g;' ecompile.cfg.example | uniq >ecompile.cfg &&
            popd >/dev/null &&
            popd >/dev/null
    ) || (echo "Could not modify pol.cfg.example or ecompile.cfg.example" && exit ${error_code[update_core_cfgs]})
}

function run_uoconvert() {
    declare -a realms=(britannia britannia-alt ilshenar malas tokuno termur)
    declare -a realm_convs=(map statics maptile)
    declare -a root_convs=(tiles landtiles multis)
    declare -a maps=()

    if ls $UODATADIR/*.uop 1>/dev/null 2>&1; then
        local IsUOPInstallation=1
    fi

    if [ ! -z $IsUOPInstallation ]; then
        maps=($(ls $UODATADIR/map?LegacyMUL.uop))
    else
        maps=($(ls $UODATADIR/map?.mul))

        local map0size=$(stat -c%s "${maps[0]}" 2>/dev/null)
        if [ "$map0size" == "" ]; then
            echo "Could not find maps" && exit ${error_code[run_uoconvert.no_maps]}
        fi
        if [ $(($map0size / 196)) -eq 393216 ]; then
            local isLegacyDimenions=1
        fi
        isLegacyDimenions=1
    fi

    if [ $REALMDIR != "$SHARDDIR/realm" ] && [ ! -d $REALMDIR ]; then
        echo "Making Realm directory $REALMDIR"
        mkdir -p $REALMDIR || (echo "Could not create realm directory $REALMDIR" && exit ${error_code[run_uoconvert.create_realmdir]})
    fi

    pushd $SHARDDIR >/dev/null
    # ./uoconvert map realm=britannia mapid=0 usedif=1 width=7168|6144

    echo "Using legacy dimensions: ${isLegacyDimenions:-0}"
    echo "Is UOP Installation: ${IsUOPInstallation:-0}"

    for mapid in ${!maps[@]}; do
        local realm=${realms[$mapid]}
        local realmcfg="$REALMDIR/$realm/realm.cfg"
        if [ -f $realmcfg ]; then
            echo "Realm already converted: $realmcfg"
        else
            for cmd in ${!realm_convs[@]}; do
                local type=${realm_convs[cmd]}
                local convertcmd="./uoconvert $type realm=${realm} mapid=${mapid}"
                if [ $type == "map" ]; then
                    convertcmd="$convertcmd usedif=1 readuop=${IsUOPInstallation:-0}"
                fi

                if ([ $realm == "britannia" ] || [ $realm == "britannia-alt" ]) && [ -z $isLegacyDimenions ]; then
                    convertcmd="$convertcmd width=7168"
                fi
                echo "Converting realm $realm: $convertcmd"
                ($convertcmd) || (echo "uoconvert failed" && exit ${error_code[run_uoconvert.convert_cmd]})
            done
            if [ $REALMDIR != "$SHARDDIR/realm" ]; then
                echo "Moving realm $realm to $REALMDIR"
                mv $SHARDDIR/realm/$realm $REALMDIR || (echo "Could not move $realm to $REALMDIR" && exit ${error_code[run_uoconvert.move_convert]})
            fi
        fi
    done

    for cmd in ${!root_convs[@]}; do
        local type=${root_convs[cmd]}
        local convertcmd="./uoconvert $type"
        local typecfg="$SHARDDIR/config/$type.cfg"

        if [ -f $typecfg ]; then
            echo "Object $type already converted: $typecfg"
        else
            echo "Converting $type: $convertcmd"
            ($convertcmd) || (echo "uoconvert failed" && exit ${error_code[run_uoconvert.convert_cmd]})
            echo "Moving $type.cfg to $SHARDDIR/config"
            mv $SHARDDIR/$type.cfg $SHARDDIR/config || (echo "Could not move $SHARDDIR/$type.cfg to $REALMDIR" && exit ${error_code[run_uoconvert.move_convert]})
        fi
    done

    popd >/dev/null
}

function get_distro() {

    if [ -f $SHARDDIR/config/cmds.cfg ]; then
        echo "File 'config/cmds.cfg' already exists in $SHARDDIR. Skip fetching distro..."
        return
    fi

    echo "Downloading $DISTROZIP"
    local zipbase=$(basename $DISTROZIP)

    if [ -f $zipbase ]; then
        echo "File already exists: $(readlink -f $zipbase)"
    else
        curl -L -O -N $DISTROZIP || (echo "Could not download $DISTROZIP" && exit ${error_code[get_distro.download]})
    fi

    unzip-strip $zipbase Distro || (echo "Could not unzip $zipbase" && exit ${error_code[get_distro.unzip]})

    cp -vnpr Distro/* $SHARDDIR || (echo "Could not merge Distro into $SHARDDIR" && exit ${error_code[get_distro.merge]})
}

function ecompile_scripts() {
    echo "Compiling scripts in $SHARDDIR"
    $SHARDDIR/scripts/ecompile -Au >/tmp/ecompile.log 2>&1 || (tail -n +3 /tmp/ecompile.log && echo "Could not compile scripts in $SHARDDIR" && exit ${error_code[ecompile]})
    sed -n '/^Compilation Summary:$/,$p' /tmp/ecompile.log
}

function create_accountstxt() {
    # read -p "Account name: " accountname
    # read -p "Account password: " accountpass
    local accountname="admin"
    local accountpass="admin"
    local accountstxt="$SHARDDIR/data/accounts.txt"

    if [ -f $accountstxt ] && [ "$(grep -E "^\s*Name\s+admin\s*$" $accountstxt)" != "" ]; then
        echo "Account 'admin' already exists in 'data/accounts.txt' in $SHARDDIR. Skip creating admin account..."
        return
    fi
    echo "Creating initial account '${accountname}'"
    local passhash=$(echo -n "${accountname}${accountpass}" | md5sum | awk '{print $1}')
    cat >$accountstxt <<EOL
Account
{
	Name	admin
	PasswordHash	$passhash
	Enabled	1
	Banned	0
	DefaultCmdLevel	test
}
EOL
}

function create_poltxt() {
    # read -p "Account name: " accountname
    # read -p "Account password: " accountpass
    local accountname="admin"
    local accountpass="admin"

    if [ -f $SHARDDIR/data/pol.txt ]; then
        echo "File 'data/pol.txt' already exists in $SHARDDIR. Skip configuring pol.txt data file..."
        return
    fi
    echo "Creating initial pol.txt data file"
    cat >$SHARDDIR/data/pol.txt <<EOL
System
{
	CoreVersion	100
}
EOL
}

function start_pol() {
    pushd $SHARDDIR >/dev/null
    ./pol
    popd >/dev/null
    echo "POL finished."
}

# Unused..
# function get_client_version {
#     local CLIENT_VERSION=$(exiftool -s -s -s -ProductVersionNumber $UODATADIR/client.exe)
#     if [ "$CLIENT_VERSION" == "" ]
#     then
#         echo "Could not get client version, assuming version 4" && echo "4"
#     else
#         echo ${CLIENT_VERSION:0:1}
#     fi
# }
# echo "Got client version: $(get_client_version)"

install_deps

ensure_shard

get_core

update_core_cfgs

run_uoconvert

get_distro

ecompile_scripts

create_accountstxt

create_poltxt

start_pol

#1036288
#size = 3188736, isHSA = (size-428032) % 1188 != 0 && (size-493568) % 1316 == 0, nblocks = isHSA ? (size - 493568) / 1316 : (size - 428032)/1188, maxTileID = 32*nblocks - 1, [isHSA, maxTileID.toString(16)]
