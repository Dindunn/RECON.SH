#!/bin/bash

# Visual color indicators for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help/Usage guide
usage() {
    echo "Usage: $0 -d <domain>"
    echo "Options:"
    echo "  -d    Target domain (e.g., target.com)"
    exit 1
}

# Parse command line flags
while getopts "d:" opt; do
    case ${opt} in
        d ) DOMAIN=$OPTARG;;
        * ) usage;;
    esac
done

if [ -z "$DOMAIN" ]; then
    usage
fi

# 1. Pipeline Directory Setup
OUTPUT_DIR="results/$DOMAIN"
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}[*] Launching Recon Pipeline for: $DOMAIN${NC}"
echo -e "${BLUE}[*] Outputs will save to: $OUTPUT_DIR/${NC}\n"

# 2. Subdomain Enumeration (Passive)
echo -e "${GREEN}[+] Running passive subdomain enumeration (subfinder)...${NC}"
subfinder -d "$DOMAIN" -silent -o "$OUTPUT_DIR/subdomains.txt"
echo -e "${GREEN}[✔] Found $(wc -l < "$OUTPUT_DIR/subdomains.txt") total subdomains.${NC}\n"

# 3. Live Host Probing (HTTP/HTTPS)
if [ -s "$OUTPUT_DIR/subdomains.txt" ]; then
    echo -e "${GREEN}[+] Checking for live HTTP/HTTPS services (httpx)...${NC}"
    httpx -l "$OUTPUT_DIR/subdomains.txt" -silent -o "$OUTPUT_DIR/live_hosts.txt"
    echo -e "${GREEN}[✔] Identified $(wc -l < "$OUTPUT_DIR/live_hosts.txt") active web services.${NC}\n"
else
    echo -e "${RED}[!] No subdomains discovered to probe.${NC}"
fi

# 4. URL & Endpoint Harvesting (Historical Data)
echo -e "${GREEN}[+] Scraping historical URLs from web archives (waybackurls)...${NC}"
cat "$OUTPUT_DIR/subdomains.txt" | waybackurls > "$OUTPUT_DIR/wayback_raw.txt"

# Deduplicate URLs safely
if [ -s "$OUTPUT_DIR/wayback_raw.txt" ]; then
    if command -v anew &> /dev/null; then
        cat "$OUTPUT_DIR/wayback_raw.txt" | anew "$OUTPUT_DIR/wayback_urls.txt" > /dev/null
    else
        sort -u "$OUTPUT_DIR/wayback_raw.txt" > "$OUTPUT_DIR/wayback_urls.txt"
    fi
    rm "$OUTPUT_DIR/wayback_raw.txt"
    echo -e "${GREEN}[✔] Processed $(wc -l < "$OUTPUT_DIR/wayback_urls.txt") unique historical URLs.${NC}\n"
fi

echo -e "${BLUE}[*] Pipeline complete. Happy hunting! Check your output files in $OUTPUT_DIR/${NC}

# 5. High-Value Endpoint & Parameter Filtering
if [ -s "$OUTPUT_DIR/wayback_urls.txt" ]; then
    echo -e "${GREEN}[+] Filtering Wayback data for high-value targets...${NC}"
    
    # Extract URLs with parameters (potential XSS/SQLi/SSRF entry points)
    grep -E '\?.*\=' "$OUTPUT_DIR/wayback_urls.txt" | sort -u > "$OUTPUT_DIR/param_endpoints.txt"
    
    # Extract interesting extensions (Configuration files, JSON data, JS files)
    grep -E '\.(json|js|bak|conf|config|xml|sql|xls|xlsx)$' "$OUTPUT_DIR/wayback_urls.txt" | sort -u > "$OUTPUT_DIR/interesting_extensions.txt"
    
    echo -e "${GREEN}[✔] Isolated $(wc -l < "$OUTPUT_DIR/param_endpoints.txt") URLs with active parameters.${NC}"
    echo -e "${GREEN}[✔] Isolated $(wc -l < "$OUTPUT_DIR/interesting_extensions.txt") files with sensitive extensions.${NC}\n"
else
    echo -e "${RED}[!] No historical URLs found to filter.${NC}"
fi
