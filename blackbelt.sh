#!/bin/bash
INPUT=$1
THREADS=600
OUT=godmode_recon

mkdir -p $OUT
ulimit -n 1000000
export GOMAXPROCS=$(nproc)

sysctl -w net.core.somaxconn=65535 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_max_syn_backlog=65535 >/dev/null 2>&1
sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1

cat $INPUT | xargs -P 150 -I{} sh -c '
proxychains4 subfinder -d {} -silent
proxychains4 assetfinder --subs-only {}
proxychains4 chaos -d {}
proxychains4 amass enum -passive -d {}
' >> $OUT/subs_raw.txt

sort -u $OUT/subs_raw.txt > $OUT/subdomains.txt

proxychains4 dnsx 
-l $OUT/subdomains.txt 
-silent 
-threads $THREADS 
-o $OUT/resolved.txt

proxychains4 naabu 
-l $OUT/resolved.txt 
-top-ports 1000 
-rate 12000 
-o $OUT/open_ports.txt

proxychains4 httpx 
-l $OUT/resolved.txt 
-silent 
-threads $THREADS 
-title 
-tech-detect 
-status-code 
-ip 
-cdn 
-server 
-o $OUT/live_hosts.txt

cat $OUT/live_hosts.txt | gau >> $OUT/urls_raw.txt
cat $OUT/live_hosts.txt | waybackurls >> $OUT/urls_raw.txt

proxychains4 katana 
-l $OUT/live_hosts.txt 
-depth 5 
-js-crawl 
-jsluice 
-automatic-form-fill 
-silent 
-o $OUT/crawled_urls.txt

cat $OUT/urls_raw.txt $OUT/crawled_urls.txt | sort -u > $OUT/all_urls.txt

grep "=" $OUT/all_urls.txt | sort -u > $OUT/params.txt

grep ".js" $OUT/all_urls.txt | sort -u > $OUT/js_files.txt

cat $OUT/js_files.txt | xargs -P 120 -I{} curl -s {} | grep -E "apikey|token|secret|password|auth|client_secret|access_key|aws_access_key_id|aws_secret_access_key" >> $OUT/js_secrets.txt

cat $OUT/live_hosts.txt | xargs -P 80 -I{} proxychains4 ffuf -u {}/FUZZ -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt -t 120 -mc all -fs 0 -s >> $OUT/ffuf_results.txt

cat $OUT/params.txt | dalfox pipe --silence >> $OUT/xss_results.txt

proxychains4 nuclei 
-l $OUT/live_hosts.txt 
-t ~/nuclei-templates 
-c 600 
-rate-limit 2000 
-o $OUT/nuclei_results.txt
