# PageCamel Web Connection Performance Optimizations

**Date:** 2025-12-19
**Issue:** Web connections were slow to connect/react

## Problem Summary

Multiple performance anti-patterns were identified across the frontend, backend, and HTTP handler layers:

- Busy-wait polling with `sleep(0.01)` instead of proper `select()` timeouts
- Byte-by-byte socket reading causing excessive syscalls
- Inadequate listen queue sizes (20 vs max_childs 200-800)
- SSL session cache disabled, preventing session resumption
- O(n²) string operations in header parsing and buffer management
- Redundant timeout mechanisms (alarm + select + manual checks)
- File descriptor leaks in forking code

## Files Modified

- `lib/PageCamel/CMDLine/WebFrontend.pm` - SSL frontend, connection forwarding
- `lib/PageCamel/CMDLine/WebBackend.pm` - Backend forking server
- `lib/PageCamel/WebBase.pm` - HTTP parsing, response generation
- `lib/PageCamel/Helpers/WebPrint.pm` - Socket write helper
- `lib/PageCamel/Web/Mercurial/Proxy.pm` - Mercurial HTTP proxy

---

## Phase 1: Quick Wins

### 1.1 Listen Queue Sizes

**Files:** WebFrontend.pm, WebBackend.pm

**Change:** Increased listen queue from hardcoded `20` to use `max_childs` config value or default `128`.

**Why:** Small listen queue causes connection drops under burst load. Queue should match expected concurrent connection attempts.

**Rollback:** Change `Listen =>` back to `20` in both files.

### 1.2 Socket Options

**File:** WebFrontend.pm (after accept)

**Change:** Added after socket accept:
```perl
setsockopt($client, IPPROTO_TCP, TCP_NODELAY, 1);
setsockopt($client, SOL_SOCKET, SO_KEEPALIVE, 1);
```

**Why:**
- `TCP_NODELAY` disables Nagle's algorithm for lower latency on small packets
- `SO_KEEPALIVE` detects dead connections via TCP keepalive probes

**Rollback:** Remove the two `setsockopt` lines after accept.

### 1.3 SSL Session Tickets

**File:** WebFrontend.pm

**Change:**
- Generate shared ticket key in parent before accept loop (using `/dev/urandom`)
- Set up `CTX_set_tlsext_ticket_getkey_cb` callback to share key across forked children
- Removed `SSL_SESS_CACHE_OFF` and `OP_NO_TICKET` settings

**Why:** Enables TLS session resumption across all child processes. Returning clients can resume in 1 RTT instead of full handshake (2-3 RTT).

**Verification:** `openssl s_client -connect host:443 -reconnect` should show "Reused" on reconnection.

**Rollback:** Remove ticket key generation, remove callback setup, restore `SSL_SESS_CACHE_OFF` and `OP_NO_TICKET`.

---

## Phase 2: Replace Busy-Wait Polling

### 2.1 WebBase.pm readheader()

**Change:**
- Added `IO::Select` with calculated remaining timeout
- Replaced `sleep(0.01)` busy-wait with `$select->can_read($remaining)`
- Fixed EOF handling: check `sysread` return value, not buffer content
- Added check that line ends with `\n` before returning (prevents partial lines)

**Why:** Eliminates CPU waste from busy-waiting. Proper EOF detection prevents returning incomplete headers.

### 2.2 WebBase.pm get_request_body()

**Change:**
- Use `IO::Select` with timeout instead of `sleep(0.01)`
- Changed from string concatenation to array push + join (O(n) vs O(n²))

**Why:** Large POST bodies were causing O(n²) string allocations.

### 2.3 WebBackend.pm readFrontendheader()

**Change:** Use `IO::Select` with timeout instead of `sleep(0.01)`.

### 2.4 WebBackend.pm run()

**Change:** Added 1-second timeout to `can_read()` call in accept loop.

**Why:** Without timeout, the loop would block indefinitely, preventing clean shutdown.

### 2.5 WebPrint.pm write loop

**Change:**
- Added `IO::Select` for write readiness
- Use `$select->can_write($remaining)` instead of `sleep(0.01)` on EWOULDBLOCK

**Why:** Eliminates busy-wait when socket buffer is full.

---

## Phase 3: Header Parsing Performance

**File:** WebFrontend.pm `parseheaders()`

**Change:** Replaced character-by-character parsing with `split(/\r?\n/, $rawheaders)`.

**Before (O(n²)):**
```perl
my @bytes = split//, $rawheaders;
while(scalar @bytes) {
    my $char = shift @bytes;  # O(n) shift in loop = O(n²)
    ...
}
```

**After (O(n)):**
```perl
my @lines = split(/\r?\n/, $rawheaders);
foreach my $line (@lines) {
    last if $line eq '';
    push @headers, $line;
}
```

---

## Phase 4: Buffer Management

**File:** WebFrontend.pm data forwarding loop

### Offset Tracking

**Change:** Use `syswrite($fh, $buffer, $length, $offset)` with offset tracking instead of repeated `substr($buffer, $written)`.

**Before:** Each write copied remaining buffer (~600 copies per 10MB)
**After:** Single `substr` at end of write loop

### Buffer Size Limits

**Change:** Added 50MB limit per buffer. Skip reading from source if destination buffer >= 50MB.

```perl
my $max_buffer_size = 50_000_000;
next if length($toclientbuffer) >= $max_buffer_size;
```

**Why:** Prevents memory exhaustion with slow clients. Applies natural TCP back-pressure.

---

## Phase 5: Timeout Handling

**File:** WebFrontend.pm

### Removed alarm()

**Change:** Removed `alarm($readtimeout)` and `alarm(0)` wrapper around header reading.

**Why:**
- `alarm()` is a global resource (only one at a time)
- Can interfere with other code using alarm
- Already have proper `select()` timeouts

### EINTR Handling

**Change:** Added `use Errno qw(:POSIX)` and EINTR checks after `can_read()`:

```perl
if(!@connections && $!{EINTR}) {
    next;  # Signal interrupted, retry
}
```

**Why:** Signals can interrupt `select()`. Without EINTR handling, this could cause spurious timeouts or errors.

### Removed sleep(0.01) in Header Reading

**Change:** Removed busy-wait, rely on `can_read($remaining)` timeout.

---

## Phase 6: Process Management

**File:** WebBackend.pm

### Close Socket in Parent After Fork

**Change:** Added `$client->close;` in parent branch after fork.

**Why:** Prevents file descriptor leak. Without this, parent keeps fd open indefinitely.

### Simplified REAPER Signal Handler

**Change:**
- Converted to anonymous sub
- Removed handler reinstallation (not needed on Perl 5.8+)

```perl
$SIG{CHLD} = sub {
    while ((my $pid = waitpid(-1, WNOHANG)) > 0) {
        $childcount--;
    }
};
```

### Simplified endprogram()

**Change:** Removed bizarre infinite loop with `kill 9` and `sleep(10)`.

**Before:**
```perl
sleep(0.3);
while(1) {
    kill 9, $PID;
    POSIX::_exit(0);
    sleep(10);
}
```

**After:**
```perl
if(defined($header->{pid}) && $header->{pid} > 0) {
    kill 'USR1', $header->{pid};
}
POSIX::_exit(0);
```

---

## Troubleshooting

### "Illegal header line" errors

If these appear, check:
1. WebBase.pm `readheader()` - ensure EOF handling is correct
2. WebBase.pm `parse_header_line()` - regex is `^(\S+)\:\s*(.*)$` (lenient)
3. Debug log now shows escaped content of failing header

### SSL session resumption not working

Verify with: `openssl s_client -connect host:443 -reconnect`

Check:
1. Ticket key generation in WebFrontend.pm `run()` before accept loop
2. Callback setup in SSL context creation
3. `SSL_SESS_CACHE_OFF` and `OP_NO_TICKET` are NOT set

### Connection drops under load

Check:
1. Listen queue size matches max_childs
2. `lsof -p <pid> | wc -l` for fd leaks
3. Child count tracking in REAPER

### High CPU with idle connections

If busy-wait returns, check:
1. All `sleep(0.01)` removed
2. All `can_read()` / `can_write()` have proper timeouts
3. No tight loops without select()

---

## Phase 7: Mercurial Proxy Optimizations

**File:** `lib/PageCamel/Web/Mercurial/Proxy.pm`

### Socket Options

**Change:** Added `Timeout => 30` to socket creation and `TCP_NODELAY` after connect.

```perl
my $socket = IO::Socket::IP->new(
    ...
    Timeout => 30,
);
setsockopt($socket, IPPROTO_TCP, TCP_NODELAY, 1);
```

**Why:** Prevents indefinite blocking on connect, reduces latency.

### readsocketline() - Busy-Wait Fix

**Change:** Added `IO::Select` to wait for data instead of busy-waiting with `recv()` in a tight loop.

**Before:** CPU spinning when no data available
**After:** Proper `$select->can_read($remaining)` with timeout

### readPlain() - Busy-Wait and O(n²) Fix

**Change:**
- Added `IO::Select` for proper waiting
- Changed from string concatenation to `@chunks` array + `join()`

**Before:** `$content .= $partial` in loop (O(n²))
**After:** `push @chunks, $partial` then `join('', @chunks)` (O(n))

### readChunked() - O(n²) Fix

**Change:** Same array + join pattern for chunked transfer encoding.

**Rollback:** Revert the four functions to their original implementations (no IO::Select, string concatenation).

---

## Phase 8: Request Body Block Size

**File:** `lib/PageCamel/WebBase.pm`

**Change:** Increased block size from 1024 to 65536 (64KB) for:
- `get_request_body()` call (line 1305)
- `stream_request_body()` call (line 1403)

**Before:** 1024 bytes per read = ~10,000 syscalls for 10MB upload
**After:** 65536 bytes per read = ~160 syscalls for 10MB upload

**Why:** 64x reduction in syscall overhead for large uploads.

**Rollback:** Change `65536` back to `1024` at lines 1305 and 1403.

---

## Performance Verification

1. **SSL handshake:** `time openssl s_client -connect host:443` (should be <100ms)
2. **Session resumption:** Second connection in `openssl s_client -reconnect` should show "Reused"
3. **CPU usage:** `top` should show low CPU during idle connections
4. **Connection burst:** Test with `ab -n 1000 -c 100 https://host/` - no dropped connections
5. **Memory:** Monitor during large file transfers - should stay bounded
