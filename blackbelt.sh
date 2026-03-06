#!/bin/bash

set -e
set -o pipefail

INPUT=$1
THREADS=700

BASE=$HOME/godmode_v2
TOOLS=$BASE/tools
DATA=$BASE/data
RESOLVERS=$BASE/resolvers.txt
WORDLIST=$BASE/subdomains.txt

mkdir -p $TOOLS
mkdir -p $DATA

ulimit -n 1000000
export GOMAXPROCS=$(nproc)
export GOMEMLIMIT=8GiB

sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535
sysctl -w net.ipv4.ip_local_port_range="1024 65535"
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_fin_timeout=15

apt update

apt install -y \
git curl wget jq tmux parallel dnsutils \
build-essential unzip proxychains4 python3 python3-pip \
libpcap-dev golang-go

mkdir -p $HOME/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$HOME/go/bin

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
go install github.com/d3mondev/puredns/v2@latest
go install github.com/projectdiscovery/subzy/cmd/subzy@latest

nuclei -update-templates

mkdir -p /usr/share/wordlists/dirbuster

wget -q https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/directory-list-2.3-medium.txt \
-O /usr/share/wordlists/dirbuster/dir.txt

wget -q https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt \
-O $RESOLVERS

wget -q https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/subdomains-top1million-5000.txt \
-O $WORDLIST

git clone https://github.com/blechschmidt/massdns.git $TOOLS/massdns
cd $TOOLS/massdns
make
cd

while true
do

RUN=$(date +%s)
OUT=$DATA/run_$RUN

mkdir -p $OUT/{subs,resolved,live,ports,urls,js,secrets,params,fuzz,xss,nuclei,takeover}

cat $INPUT | parallel -j 120 '

subfinder -d {} -silent
assetfinder --subs-only {}
chaos -d {}
amass enum -passive -d {}

curl -s https://crt.sh/\?q=%25.{}\\&output=json \
| jq -r ".[].name_value" | sed "s/\*\.//g"

curl -s https://rapiddns.io/subdomain/{}?full=1 \
| grep -oP "(?<=<td>)[^<]+" | grep {}

' | anew $OUT/subs/passive.txt

cat $INPUT | parallel -j 80 '

puredns bruteforce '"$WORDLIST"' {} \
-r '"$RESOLVERS"' \
-w -

' | anew $OUT/subs/bruteforce.txt

cat $OUT/subs/passive.txt $OUT/subs/bruteforce.txt | sort -u > $OUT/subs/all.txt

$TOOLS/massdns/bin/massdns \
-r $RESOLVERS \
-t A \
-o S \
-w $OUT/subs/massdns.txt \
$OUT/subs/all.txt

cut -d" " -f1 $OUT/subs/massdns.txt | sed "s/\.$//" | sort -u > $OUT/resolved/resolved.txt

httpx \
-l $OUT/resolved/resolved.txt \
-title \
-status-code \
-tech-detect \
-ip \
-server \
-cdn \
-follow-redirects \
-random-agent \
-silent \
-threads $THREADS \
-o $OUT/live/live.txt

naabu \
-l $OUT/resolved/resolved.txt \
-top-ports 1000 \
-rate 20000 \
-o $OUT/ports/ports.txt

subzy run \
--targets $OUT/resolved/resolved.txt \
--hide_fails \
--output $OUT/takeover/takeovers.txt

cat $OUT/live/live.txt | gau >> $OUT/urls/raw.txt
cat $OUT/live/live.txt | waybackurls >> $OUT/urls/raw.txt

katana \
-l $OUT/live/live.txt \
-depth 5 \
-js-crawl \
-jsluice \
-automatic-form-fill \
-silent \
-o $OUT/urls/crawl.txt

cat $OUT/urls/raw.txt $OUT/urls/crawl.txt | sort -u > $OUT/urls/all.txt

grep "=" $OUT/urls/all.txt | sort -u > $OUT/params/params.txt

grep "\.js" $OUT/urls/all.txt | sort -u > $OUT/js/js.txt

cat $OUT/js/js.txt | parallel -j 100 '

curl -s {} | grep -Ei "(apikey|token|secret|password|client_secret|access_key|aws_access_key_id|aws_secret_access_key)"

' >> $OUT/secrets/js.txt

cat $OUT/live/live.txt | parallel -j 60 '

ffuf \
-u {}/FUZZ \
-w /usr/share/wordlists/dirbuster/dir.txt \
-t 60 \
-mc all \
-fs 0 \
-s

' >> $OUT/fuzz/ffuf.txt

cat $OUT/params/params.txt | dalfox pipe --silence >> $OUT/xss/xss.txt

nuclei \
-l $OUT/live/live.txt \
-c 700 \
-rate-limit 3500 \
-o $OUT/nuclei/nuclei.txt

gowitness scan file -f $OUT/live/live.txt

find $DATA -type d -mtime +7 -exec rm -rf {} +

sleep 86400

done
