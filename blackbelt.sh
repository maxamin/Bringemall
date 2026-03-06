#!/bin/bash

# ==============================

# ☠️ BLACK BELT BUG BOUNTY RECON

# ==============================

INPUT=$1
THREADS=400
OUT=blackbelt_recon

mkdir -p $OUT
ulimit -n 200000

echo "[+] Starting Black-Belt Recon"

# ------------------------------

# 1️⃣ SUBDOMAIN ENUMERATION

# ------------------------------

echo "[+] Enumerating subdomains..."

cat $INPUT | xargs -P 80 -I{} sh -c '
proxychains4 subfinder -d {} -silent
proxychains4 assetfinder --subs-only {}
proxychains4 chaos -d {}
proxychains4 amass enum -passive -d {}
' >> $OUT/subs_raw.txt

sort -u $OUT/subs_raw.txt > $OUT/subdomains.txt

# ------------------------------

# 2️⃣ DNS RESOLUTION

# ------------------------------

echo "[+] Resolving domains..."

proxychains4 dnsx 
-l $OUT/subdomains.txt 
-silent 
-threads $THREADS 
-o $OUT/resolved.txt

# ------------------------------

# 3️⃣ PORT SCANNING

# ------------------------------

echo "[+] Scanning ports..."

proxychains4 naabu 
-l $OUT/resolved.txt 
-top-ports 1000 
-rate 5000 
-o $OUT/open_ports.txt

# ------------------------------

# 4️⃣ LIVE HOST DISCOVERY

# ------------------------------

echo "[+] Detecting live services..."

proxychains4 httpx 
-l $OUT/resolved.txt 
-silent 
-threads $THREADS 
-title 
-tech-detect 
-status-code 
-ip 
-o $OUT/live_hosts.txt

# ------------------------------

# 5️⃣ HISTORICAL URL DISCOVERY

# ------------------------------

echo "[+] Gathering historical URLs..."

cat $OUT/live_hosts.txt | gau >> $OUT/urls_raw.txt
cat $OUT/live_hosts.txt | waybackurls >> $OUT/urls_raw.txt

# ------------------------------

# 6️⃣ ADVANCED CRAWLING

# ------------------------------

echo "[+] Crawling sites..."

proxychains4 katana 
-l $OUT/live_hosts.txt 
-depth 5 
-js-crawl 
-jsluice 
-silent 
-o $OUT/crawled_urls.txt

# ------------------------------

# 7️⃣ URL MERGING

# ------------------------------

cat $OUT/urls_raw.txt $OUT/crawled_urls.txt 
| sort -u > $OUT/all_urls.txt

# ------------------------------

# 8️⃣ PARAMETER DISCOVERY

# ------------------------------

grep "=" $OUT/all_urls.txt 
| sort -u > $OUT/params.txt

# ------------------------------

# 9️⃣ JAVASCRIPT FILES

# ------------------------------

grep ".js" $OUT/all_urls.txt 
| sort -u > $OUT/js_files.txt

# ------------------------------

# 🔟 SECRET DISCOVERY

# ------------------------------

echo "[+] Searching JS secrets..."

cat $OUT/js_files.txt | 
xargs -P 80 -I{} curl -s {} 
| grep -E "apikey|token|secret|password|auth|client_secret" \

> > $OUT/js_secrets.txt

# ------------------------------

# 1️⃣1️⃣ DIRECTORY FUZZING

# ------------------------------

echo "[+] Running directory fuzzing..."

cat $OUT/live_hosts.txt | 
xargs -P 40 -I{} 
proxychains4 ffuf 
-u {}/FUZZ 
-w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt 
-t 80 
-s 
-o $OUT/ffuf_results.txt

# ------------------------------

# 1️⃣2️⃣ XSS TESTING

# ------------------------------

echo "[+] Running Dalfox..."

cat $OUT/params.txt | 
dalfox pipe 
--silence 
-o $OUT/xss_results.txt

# ------------------------------

# 1️⃣3️⃣ VULNERABILITY SCAN

# ------------------------------

echo "[+] Running Nuclei..."

proxychains4 nuclei 
-l $OUT/live_hosts.txt 
-t ~/nuclei-templates 
-c 300 
-rate-limit 800 
-o $OUT/nuclei_results.txt

echo "[+] BLACK-BELT RECON COMPLETE"
echo "[+] Results stored in $OUT"
