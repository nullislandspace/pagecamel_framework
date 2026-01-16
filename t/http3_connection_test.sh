#!/bin/bash
# HTTP/3 Connection Reuse Test Script
# Tests fetching multiple URLs with:
#   a) Single connection (connection reuse)
#   b) Separate connection per URL

CURL="/usr/local/bin/curl-h3"
BASE_URL="https://test.cavac.at"
START_PAGE="/cavacopedia"
MAX_URLS=50
TEMP_DIR="/tmp/http3_test_$$"

mkdir -p "$TEMP_DIR"

echo "=== HTTP/3 Connection Reuse Test ==="
echo "Fetching $START_PAGE to extract URLs..."

# Fetch the start page and extract URLs
$CURL --http3-only -k -s "$BASE_URL$START_PAGE" > "$TEMP_DIR/startpage.html"

if [ ! -s "$TEMP_DIR/startpage.html" ]; then
    echo "ERROR: Failed to fetch start page"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Extract href URLs from the page (relative and absolute), take first MAX_URLS
grep -oP 'href="[^"]*"' "$TEMP_DIR/startpage.html" | \
    sed 's/href="//;s/"$//' | \
    grep -v '^#' | \
    grep -v '^javascript:' | \
    grep -v '^mailto:' | \
    head -n $MAX_URLS > "$TEMP_DIR/urls.txt"

URL_COUNT=$(wc -l < "$TEMP_DIR/urls.txt")
echo "Found $URL_COUNT URLs to test"
echo ""

if [ "$URL_COUNT" -lt 10 ]; then
    echo "ERROR: Too few URLs found. Page content:"
    head -50 "$TEMP_DIR/startpage.html"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Build full URLs (handle relative vs absolute)
> "$TEMP_DIR/full_urls.txt"
while read -r url; do
    if [[ "$url" == http* ]]; then
        echo "$url" >> "$TEMP_DIR/full_urls.txt"
    elif [[ "$url" == /* ]]; then
        echo "$BASE_URL$url" >> "$TEMP_DIR/full_urls.txt"
    else
        echo "$BASE_URL/$url" >> "$TEMP_DIR/full_urls.txt"
    fi
done < "$TEMP_DIR/urls.txt"

echo "=== Test A: Single Connection (Connection Reuse) ==="
echo "Fetching $URL_COUNT URLs on a single HTTP/3 connection..."

# Build curl command with all URLs for single connection
CURL_ARGS=""
while read -r url; do
    CURL_ARGS="$CURL_ARGS -o /dev/null $url"
done < "$TEMP_DIR/full_urls.txt"

START_TIME=$(date +%s.%N)
$CURL --http3-only -k -s -w "URL: %{url_effective}\nHTTP Code: %{http_code}\nTime: %{time_total}s\nSize: %{size_download} bytes\n---\n" $CURL_ARGS > "$TEMP_DIR/single_conn.log" 2>&1
SINGLE_EXIT=$?
END_TIME=$(date +%s.%N)
SINGLE_TOTAL=$(echo "$END_TIME - $START_TIME" | bc)

# Count successful requests
SINGLE_SUCCESS=$(grep -c "HTTP Code: [23]" "$TEMP_DIR/single_conn.log")
SINGLE_FAIL=$(grep -c "HTTP Code: 0" "$TEMP_DIR/single_conn.log")

echo "Exit code: $SINGLE_EXIT"
echo "Successful responses: $SINGLE_SUCCESS"
echo "Failed responses: $SINGLE_FAIL"
echo "Total time: ${SINGLE_TOTAL}s"
echo ""

# Show first few and last few results
echo "First 3 results:"
head -15 "$TEMP_DIR/single_conn.log"
echo "..."
echo "Last 3 results:"
tail -15 "$TEMP_DIR/single_conn.log"
echo ""

echo "=== Test B: Separate Connections (One per URL) ==="
echo "Fetching $URL_COUNT URLs with separate HTTP/3 connections..."

START_TIME=$(date +%s.%N)
MULTI_SUCCESS=0
MULTI_FAIL=0
> "$TEMP_DIR/multi_conn.log"

while read -r url; do
    RESULT=$($CURL --http3-only -k -s -o /dev/null -w "URL: %{url_effective}\nHTTP Code: %{http_code}\nTime: %{time_total}s\nSize: %{size_download} bytes\n---\n" "$url" 2>&1)
    echo "$RESULT" >> "$TEMP_DIR/multi_conn.log"

    HTTP_CODE=$(echo "$RESULT" | grep "HTTP Code:" | cut -d' ' -f3)
    if [[ "$HTTP_CODE" =~ ^[23] ]]; then
        ((MULTI_SUCCESS++))
    else
        ((MULTI_FAIL++))
    fi
done < "$TEMP_DIR/full_urls.txt"

END_TIME=$(date +%s.%N)
MULTI_TOTAL=$(echo "$END_TIME - $START_TIME" | bc)

echo "Successful responses: $MULTI_SUCCESS"
echo "Failed responses: $MULTI_FAIL"
echo "Total time: ${MULTI_TOTAL}s"
echo ""

# Show first few and last few results
echo "First 3 results:"
head -15 "$TEMP_DIR/multi_conn.log"
echo "..."
echo "Last 3 results:"
tail -15 "$TEMP_DIR/multi_conn.log"
echo ""

echo "=== Summary ==="
echo "URLs tested: $URL_COUNT"
echo ""
echo "Single Connection (reuse):"
echo "  - Success: $SINGLE_SUCCESS, Failed: $SINGLE_FAIL"
echo "  - Total time: ${SINGLE_TOTAL}s"
if [ "$URL_COUNT" -gt 0 ]; then
    AVG_SINGLE=$(echo "scale=3; $SINGLE_TOTAL / $URL_COUNT" | bc)
    echo "  - Average per URL: ${AVG_SINGLE}s"
fi
echo ""
echo "Separate Connections:"
echo "  - Success: $MULTI_SUCCESS, Failed: $MULTI_FAIL"
echo "  - Total time: ${MULTI_TOTAL}s"
if [ "$URL_COUNT" -gt 0 ]; then
    AVG_MULTI=$(echo "scale=3; $MULTI_TOTAL / $URL_COUNT" | bc)
    echo "  - Average per URL: ${AVG_MULTI}s"
fi
echo ""

if [ "$SINGLE_FAIL" -eq 0 ] && [ "$MULTI_FAIL" -eq 0 ]; then
    echo "RESULT: Both tests PASSED - all requests successful"
    SPEEDUP=$(echo "scale=2; $MULTI_TOTAL / $SINGLE_TOTAL" | bc)
    echo "Connection reuse is ${SPEEDUP}x faster than separate connections"
elif [ "$SINGLE_FAIL" -gt 0 ] && [ "$MULTI_FAIL" -eq 0 ]; then
    echo "RESULT: Single connection test FAILED ($SINGLE_FAIL failures)"
    echo "        Separate connections test PASSED"
elif [ "$SINGLE_FAIL" -eq 0 ] && [ "$MULTI_FAIL" -gt 0 ]; then
    echo "RESULT: Single connection test PASSED"
    echo "        Separate connections test FAILED ($MULTI_FAIL failures)"
else
    echo "RESULT: Both tests had failures"
    echo "        Single connection: $SINGLE_FAIL failures"
    echo "        Separate connections: $MULTI_FAIL failures"
fi

# Cleanup
rm -rf "$TEMP_DIR"
