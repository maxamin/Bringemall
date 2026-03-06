#!/bin/bash

set -e
set -o pipefail

INPUT=$1
THREADS=800

BASE=$HOME/godmode_recon
TOOLS=$BASE/tools
DATA=$BASE/data
RESOLVERS=$BASE/resolvers.txt

mkdir -p $TOOLS
mkdir -p $DATA

############################################
# SYSTEM OPTIMIZATION
############################################

ulimit -n 1000000
export GOMAXPROCS=$(nproc)

sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535
sysctl -w net.ipv4.ip_local_port_range="1024 65535"

############################################
# INSTALL DEPENDENCIES
############################################

apt update

apt install -y \
git curl wget jq tmux parallel \
dnsutils build-essential unzip \
proxychains4 python3 python3-pip \
libpcap-dev golang-go

mkdir -p $HOME/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$HOME/go/bin

############################################
# INSTALL GO TOOLS
############################################

go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/tomnomnom/assetfinder@latest
go install github.com/owasp-amass/amass/v4/...@master
go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
go install github.com/projectdiscovery/katana/cmd/katana@latest
go install github.com/lc/gau/v2/cmd/gau@latest
go install github.com/tomnomnom/waybackurls@latest
go install github.com/hahwul/dalfox/v2@latest
go install github.com/ffuf/ffuf/v2@latest
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/projectdiscovery/chaos-client/cmd/chaos@latest
go install github.com/tomnomnom/anew@latest
go install github.com/sensepost/gowitness@latest
go install github.com/projectdiscovery/uncover/cmd/uncover@latest
go install github.com/projectdiscovery/mapcidr/cmd/mapcidr@latest

############################################
# NUCLEI TEMPLATES
############################################

nuclei -update-templates

############################################
# WORDLISTS
############################################

mkdir -p /usr/share/wordlists/dirbuster

wget -q https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/directory-list-2.3-medium.txt \
-O /usr/share/wordlists/dirbuster/dir.txt

############################################
# RESOLVERS
############################################

wget -q https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt \
-O $RESOLVERS

############################################
# RECON LOOP
############################################

while true
do

RUN=$(date +%s)
OUT=$DATA/run_$RUN

mkdir -p $OUT/{subs,resolved,live,ports,urls,js,secrets,params,fuzz,xss,nuclei}

############################################
# SUBDOMAIN ENUMERATION
############################################

cat $INPUT | parallel -j 150 '

subfinder -d {} -silent
assetfinder --subs-only {}
chaos -d {}
amass enum -passive -d {}

curl -s https://crt.sh/\?q=%25.{}\\&output=json \
| jq -r ".[].name_value" \
| sed "s/\*\.//g"

curl -s https://rapiddns.io/subdomain/{}?full=1 \
| grep -oP "(?<=<td>)[^<]+" | grep {}

' | anew $OUT/subs/all_subdomains.txt

############################################
# DNS RESOLUTION
############################################

dnsx \
-l $OUT/subs/all_subdomains.txt \
-r $RESOLVERS \
-silent \
-threads $THREADS \
-o $OUT/resolved/resolved.txt

############################################
# HTTP PROBING
############################################

httpx \
-l $OUT/resolved/resolved.txt \
-title \
-status-code \
-tech-detect \
-ip \
-server \
-cdn \
-random-agent \
-follow-redirects \
-silent \
-threads $THREADS \
-o $OUT/live/live_hosts.txt

############################################
# PORT SCANNING
############################################

naabu \
-l $OUT/resolved/resolved.txt \
-top-ports 1000 \
-rate 20000 \
-o $OUT/ports/open_ports.txt

############################################
# URL COLLECTION
############################################

cat $OUT/live/live_hosts.txt | gau >> $OUT/urls/urls_raw.txt
cat $OUT/live/live_hosts.txt | waybackurls >> $OUT/urls/urls_raw.txt

############################################
# CRAWLING
############################################

katana \
-l $OUT/live/live_hosts.txt \
-depth 5 \
-js-crawl \
-jsluice \
-automatic-form-fill \
-silent \
-o $OUT/urls/crawled.txt

cat $OUT/urls/urls_raw.txt $OUT/urls/crawled.txt \
| sort -u > $OUT/urls/all_urls.txt

############################################
# PARAMETER DISCOVERY
############################################

grep "=" $OUT/urls/all_urls.txt \
| sort -u > $OUT/params/params.txt

############################################
# JS FILE EXTRACTION
############################################

grep "\.js" $OUT/urls/all_urls.txt \
| sort -u > $OUT/js/js_files.txt

############################################
# JS SECRET SCANNING
############################################

cat $OUT/js/js_files.txt | parallel -j 100 '

curl -s {} | grep -E \
"apikey|token|secret|password|auth|client_secret|access_key|aws_access_key_id|aws_secret_access_key"

' >> $OUT/secrets/js_secrets.txt

############################################
# DIRECTORY FUZZING
############################################

cat $OUT/live/live_hosts.txt | parallel -j 80 '

ffuf -u {}/FUZZ \
-w /usr/share/wordlists/dirbuster/dir.txt \
-t 80 \
-mc all \
-fs 0 \
-s

' >> $OUT/fuzz/ffuf.txt

############################################
# XSS SCANNING
############################################

cat $OUT/params/params.txt | dalfox pipe --silence \
>> $OUT/xss/xss.txt

############################################
# NUCLEI SCANNING
############################################

nuclei \
-l $OUT/live/live_hosts.txt \
-c 800 \
-rate-limit 4000 \
-o $OUT/nuclei/nuclei.txt

############################################
# SCREENSHOTS
############################################

gowitness scan file \
-f $OUT/live/live_hosts.txt

############################################
# RECON DELAY
############################################

sleep 86400

done
