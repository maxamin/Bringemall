#!/bin/bash

# =====================================

# ☠️ GOD-MODE BUG BOUNTY RECON FRAMEWORK

# =====================================

INPUT=$1
THREADS=500
OUT=godmode_recon

mkdir -p $OUT

# ==============================

# 🔧 PERFORMANCE TWEAKS

# ==============================

echo "[+] Applying performance tweaks..."

ulimit -n 1000000
export GOMAXPROCS=16

sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535
sysctl -w net.ipv4.ip_local_port_range="1024 65535"

echo "[+] Starting GOD MODE Recon"

# ==============================

# 1️⃣ SUBDOMAIN ENUMERATION

# ==============================

echo "[+] Enumerating subdomains..."

cat $INPUT | xargs -P 100 -I{} sh -c '
proxychains4 subfinder -d {} -silent
proxychains4 assetfinder --subs-only {}
proxychains4 chaos -d {}
proxychains4 amass enum -passive -d {}
' >> $OUT/subs_raw.txt

sort -u $OUT/subs_raw.txt > $OUT/subdomains.txt

# ==============================

# 2️⃣ DNS RESOLUTION

# ==============================

echo "[+] Resolving domains..."

proxychains4 dnsx 
-l $OUT/subdomains.txt 
-silent 
-threads $THREADS 
-o $OUT/resolved.txt

# ==============================

# 3️⃣ PORT SCANNING

# ==============================

echo "[+] Scanning ports..."

proxychains4 naabu 
-l $OUT/resolved.txt 
-top-ports 1000 
-rate 8000 
-o $OUT/open_ports.txt

# ==============================

# 4️⃣ LIVE HOST DETECTION

# ==============================

echo "[+] Probing HTTP services..."

proxychains4 httpx 
-l $OUT/resolved.txt 
-silent 
-threads $THREADS 
-title 
-tech-detect 
-status-code 
-ip 
-o $OUT/live_hosts.txt

# ==============================

# 5️⃣ HISTORICAL URL HARVESTING

# ==============================

echo "[+] Gathering historical URLs..."

cat $OUT/live_hosts.txt | gau >> $OUT/urls_raw.txt
cat $OUT/live_hosts.txt | waybackurls >> $OUT/urls_raw.txt

# ==============================

# 6️⃣ ADVANCED CRAWLING

# ==============================

echo "[+] Crawling sites..."

proxychains4 katana 
-l $OUT/live_hosts.txt 
-depth 5 
-js-crawl 
-jsluice 
-silent 
-o $OUT/crawled_urls.txt

# ==============================

# 7️⃣ URL MERGE

# ==============================

cat $OUT/urls_raw.txt $OUT/crawled_urls.txt 
| sort -u > $OUT/all_urls.txt

# ==============================

# 8️⃣ PARAMETER DISCOVERY

# ==============================

grep "=" $OUT/all_urls.txt 
| sort -u > $OUT/params.txt

# ==============================

# 9️⃣ JAVASCRIPT ANALYSIS

# ==============================

grep ".js" $OUT/all_urls.txt 
| sort -u > $OUT/js_files.txt

# ==============================

# 🔟 SECRET DISCOVERY

# ==============================

echo "[+] Extracting secrets..."

cat $OUT/js_files.txt | 
xargs -P 80 -I{} curl -s {} 
| grep -E "apikey|token|secret|password|auth|client_secret|access_key" \

> > $OUT/js_secrets.txt

# ==============================

# 1️⃣1️⃣ DIRECTORY FUZZING

# ==============================

echo "[+] Running directory fuzzing..."

cat $OUT/live_hosts.txt | 
xargs -P 50 -I{} 
proxychains4 ffuf 
-u {}/FUZZ 
-w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt 
-t 80 
-s 
-o $OUT/ffuf_results.txt

# ==============================

# 1️⃣2️⃣ XSS TESTING

# ==============================

echo "[+] Running Dalfox..."

cat $OUT/params.txt | 
dalfox pipe 
--silence 
-o $OUT/xss_results.txt

# ==============================

# 1️⃣3️⃣ MASS VULNERABILITY SCAN

# ==============================

echo "[+] Running Nuclei..."

proxychains4 nuclei 
-l $OUT/live_hosts.txt 
-t ~/nuclei-templates 
-c 500 
-rate-limit 1500 
-o $OUT/nuclei_results.txt

echo "[+] GOD MODE RECON COMPLETE"
echo "[+] Output directory: $OUT"
