#!/bin/bash

INPUT=$1
THREADS=700
BASE=$HOME/recon_vps
TOOLS=$BASE/tools
DATA=$BASE/data

mkdir -p $TOOLS
mkdir -p $DATA

apt update
apt install -y git curl wget tmux proxychains4 build-essential unzip jq python3 python3-pip dnsutils libpcap-dev golang-go

mkdir -p $HOME/go/bin
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc

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

nuclei -update-templates

mkdir -p /usr/share/wordlists/dirbuster
wget -q https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/directory-list-2.3-medium.txt -O /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt

ulimit -n 1000000
export GOMAXPROCS=$(nproc)

sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535
sysctl -w net.ipv4.ip_local_port_range="1024 65535"

while true
do

mkdir -p $DATA/run_$(date +%s)
OUT=$DATA/run_$(date +%s)

cat $INPUT | xargs -P 200 -I{} sh -c '
proxychains4 subfinder -d {} -silent
proxychains4 assetfinder --subs-only {}
proxychains4 chaos -d {}
proxychains4 amass enum -passive -d {}
' >> $OUT/subs_raw.txt

sort -u $OUT/subs_raw.txt > $OUT/subdomains.txt

proxychains4 dnsx -l $OUT/subdomains.txt -silent -threads $THREADS -o $OUT/resolved.txt

proxychains4 naabu -l $OUT/resolved.txt -top-ports 1000 -rate 15000 -o $OUT/open_ports.txt

proxychains4 httpx -l $OUT/resolved.txt -silent -threads $THREADS -title -tech-detect -status-code -ip -cdn -server -o $OUT/live_hosts.txt

cat $OUT/live_hosts.txt | gau >> $OUT/urls_raw.txt
cat $OUT/live_hosts.txt | waybackurls >> $OUT/urls_raw.txt

proxychains4 katana -l $OUT/live_hosts.txt -depth 5 -js-crawl -jsluice -automatic-form-fill -silent -o $OUT/crawled_urls.txt

cat $OUT/urls_raw.txt $OUT/crawled_urls.txt | sort -u > $OUT/all_urls.txt

grep "=" $OUT/all_urls.txt | sort -u > $OUT/params.txt

grep ".js" $OUT/all_urls.txt | sort -u > $OUT/js_files.txt

cat $OUT/js_files.txt | xargs -P 150 -I{} curl -s {} | grep -E "apikey|token|secret|password|auth|client_secret|access_key|aws_access_key_id|aws_secret_access_key" >> $OUT/js_secrets.txt

cat $OUT/live_hosts.txt | xargs -P 120 -I{} proxychains4 ffuf -u {}/FUZZ -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt -t 120 -mc all -fs 0 -s >> $OUT/ffuf_results.txt

cat $OUT/params.txt | dalfox pipe --silence >> $OUT/xss_results.txt

proxychains4 nuclei -l $OUT/live_hosts.txt -t ~/nuclei-templates -c 700 -rate-limit 2500 -o $OUT/nuclei_results.txt

sleep 86400

done
