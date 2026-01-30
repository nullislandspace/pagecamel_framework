/*
 * h3_buffer.c - Chunk-based buffer implementation for HTTP/3 response bodies
 *
 * CRITICAL: This implementation ensures pointer stability for nghttp3.
 * Chunks are NEVER reallocated - only appended and freed after ACK.
 */

#include "h3_buffer.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Debug flag - set to 1 for verbose logging */
#define H3_BUFFER_DEBUG 0

/* Test file validation - set to 1 to enable testfile_1.bin format checking
 * Test file format: 4-byte records, each is 0x01 followed by 3-byte LE record number
 * Record N at byte offset N*4 contains: 01 (N & 0xFF) ((N >> 8) & 0xFF) ((N >> 16) & 0xFF)
 */
#define H3_VALIDATE_TESTFILE 0

#if H3_VALIDATE_TESTFILE
/*
 * Validate test file data at a given stream offset.
 * Returns 0 if valid, -1 if corruption detected.
 * Only validates complete 4-byte records.
 */
static int validate_testfile_data(const uint8_t *data, size_t len, size_t stream_offset, const char *context) {
    /* Only validate if we're at a record boundary and have complete records */
    size_t start_record = stream_offset / 4;
    size_t offset_in_record = stream_offset % 4;

    /* Skip partial record at start */
    size_t skip = 0;
    if (offset_in_record != 0) {
        skip = 4 - offset_in_record;
        if (skip >= len) return 0;  /* No complete records */
        start_record++;
    }

    /* Validate complete 4-byte records */
    for (size_t i = skip; i + 4 <= len; i += 4) {
        size_t record_num = start_record + (i - skip) / 4;
        uint8_t expected[4];
        expected[0] = 0x01;
        expected[1] = (uint8_t)(record_num & 0xFF);
        expected[2] = (uint8_t)((record_num >> 8) & 0xFF);
        expected[3] = (uint8_t)((record_num >> 16) & 0xFF);

        if (data[i] != expected[0] || data[i+1] != expected[1] ||
            data[i+2] != expected[2] || data[i+3] != expected[3]) {

            /* Extract actual record number from data */
            uint32_t actual_record = data[i+1] | (data[i+2] << 8) | (data[i+3] << 16);

            fprintf(stderr, "!!! TESTFILE CORRUPTION in %s at stream_offset=%zu (record %zu) !!!\n",
                    context, stream_offset + i, record_num);
            fprintf(stderr, "    Expected: %02x %02x %02x %02x (record %zu)\n",
                    expected[0], expected[1], expected[2], expected[3], record_num);
            fprintf(stderr, "    Got:      %02x %02x %02x %02x (record %u)\n",
                    data[i], data[i+1], data[i+2], data[i+3], actual_record);
            fprintf(stderr, "    Difference: got record %u instead of %zu (delta=%ld)\n",
                    actual_record, record_num, (long)actual_record - (long)record_num);
            return -1;
        }
    }
    return 0;
}
#endif

/*
 * Chunk allocation
 */

static h3_data_chunk_t *alloc_chunk(void) {
    h3_data_chunk_t *chunk = (h3_data_chunk_t *)malloc(sizeof(h3_data_chunk_t));
    if (chunk) {
        chunk->len = 0;
        chunk->next = NULL;
    }
    return chunk;
}

static void free_chunk_list(h3_data_chunk_t *chunk) {
    while (chunk) {
        h3_data_chunk_t *next = chunk->next;
        free(chunk);
        chunk = next;
    }
}

/*
 * Buffer management
 */

void h3_buffer_init(h3_stream_buffer_t *buf) {
    buf->chunks = NULL;
    buf->write_chunk = NULL;
    buf->total_len = 0;
    buf->consumed_bytes = 0;
    buf->acked_bytes = 0;
    buf->freed_bytes = 0;
    buf->eof = 0;
}

void h3_buffer_cleanup(h3_stream_buffer_t *buf) {
    free_chunk_list(buf->chunks);
    buf->chunks = NULL;
    buf->write_chunk = NULL;
    buf->total_len = 0;
    buf->consumed_bytes = 0;
    buf->acked_bytes = 0;
    buf->freed_bytes = 0;
    buf->eof = 0;
}

int h3_buffer_write(h3_stream_buffer_t *buf, const uint8_t *data, size_t len) {
    size_t written = 0;

    if (H3_BUFFER_DEBUG && len >= 8) {
        fprintf(stderr, "h3_buffer_write: len=%zu total_before=%zu first_bytes=%02x%02x%02x%02x %02x%02x%02x%02x\n",
                len, buf->total_len,
                data[0], data[1], data[2], data[3],
                data[4], data[5], data[6], data[7]);
    }

#if H3_VALIDATE_TESTFILE
    /* Validate incoming data matches expected test file pattern */
    if (validate_testfile_data(data, len, buf->total_len, "h3_buffer_write") < 0) {
        fprintf(stderr, "h3_buffer_write: CORRUPTION DETECTED IN INCOMING DATA from backend!\n");
    }
#endif

    while (written < len) {
        /* Get or create the write chunk */
        if (!buf->write_chunk || buf->write_chunk->len >= H3_CHUNK_SIZE) {
            /* Need a new chunk */
            h3_data_chunk_t *new_chunk = alloc_chunk();
            if (!new_chunk) {
                return -1;  /* Memory allocation failure */
            }

            /* Append to list */
            if (buf->write_chunk) {
                buf->write_chunk->next = new_chunk;
            } else {
                buf->chunks = new_chunk;
            }
            buf->write_chunk = new_chunk;
        }

        /* Copy as much as fits in this chunk */
        size_t space = H3_CHUNK_SIZE - buf->write_chunk->len;
        size_t to_copy = len - written;
        if (to_copy > space) {
            to_copy = space;
        }

        memcpy(buf->write_chunk->data + buf->write_chunk->len, data + written, to_copy);
        buf->write_chunk->len += to_copy;
        buf->total_len += to_copy;
        written += to_copy;
    }

    if (H3_BUFFER_DEBUG) {
        fprintf(stderr, "h3_buffer_write: total_after=%zu\n", buf->total_len);
    }

    return 0;
}

void h3_buffer_set_eof(h3_stream_buffer_t *buf) {
    buf->eof = 1;
}

int h3_buffer_is_eof(h3_stream_buffer_t *buf) {
    return buf->eof;
}

/*
 * Read interface for nghttp3's read_data callback
 */

int h3_buffer_read(h3_stream_buffer_t *buf, h3_buffer_read_result_t *result) {
    result->base = NULL;
    result->len = 0;
    result->eof = 0;

    /* Position within remaining chunks = consumed_bytes - freed_bytes */
    size_t pos_in_chunks = buf->consumed_bytes - buf->freed_bytes;
    h3_data_chunk_t *chunk = buf->chunks;

    if (H3_BUFFER_DEBUG) {
        fprintf(stderr, "h3_buffer_read: total=%zu consumed=%zu acked=%zu freed=%zu pos_in_chunks=%zu eof=%d\n",
                buf->total_len, buf->consumed_bytes, buf->acked_bytes,
                buf->freed_bytes, pos_in_chunks, buf->eof);
    }

    /* Skip to the chunk containing the position */
    while (chunk && pos_in_chunks >= chunk->len) {
        pos_in_chunks -= chunk->len;
        chunk = chunk->next;
    }

    if (!chunk) {
        /* No more data available */
        if (buf->eof) {
            result->eof = 1;
            if (H3_BUFFER_DEBUG) {
                fprintf(stderr, "h3_buffer_read: EOF (no more chunks)\n");
            }
            return 1;  /* Data available (EOF signal) */
        }
        if (H3_BUFFER_DEBUG) {
            fprintf(stderr, "h3_buffer_read: WOULDBLOCK (pos beyond data)\n");
        }
        return 0;  /* Would block */
    }

    /* Return pointer into chunk buffer */
    size_t avail = chunk->len - pos_in_chunks;
    if (avail > 0) {
        result->base = chunk->data + pos_in_chunks;
        result->len = avail;

        /* Check if this is the last data and EOF is set */
        if (buf->eof && (buf->consumed_bytes + avail) >= buf->total_len) {
            result->eof = 1;
        }

        if (H3_BUFFER_DEBUG && avail >= 8) {
            fprintf(stderr, "h3_buffer_read: returning %zu bytes at stream_offset=%zu, first=%02x%02x%02x%02x %02x%02x%02x%02x eof=%d\n",
                    avail, buf->consumed_bytes,
                    result->base[0], result->base[1], result->base[2], result->base[3],
                    result->base[4], result->base[5], result->base[6], result->base[7],
                    result->eof);
        }

#if H3_VALIDATE_TESTFILE
        /* Validate data we're returning matches expected test file pattern */
        if (validate_testfile_data(result->base, avail, buf->consumed_bytes, "h3_buffer_read") < 0) {
            fprintf(stderr, "h3_buffer_read: CORRUPTION DETECTED IN OUTGOING DATA to nghttp3!\n");
            fprintf(stderr, "    Buffer state: total=%zu consumed=%zu acked=%zu freed=%zu pos_in_chunks=%zu\n",
                    buf->total_len, buf->consumed_bytes, buf->acked_bytes, buf->freed_bytes, pos_in_chunks);
        }
#endif

        return 1;  /* Data available */
    }

    /* Should not reach here, but handle gracefully */
    if (buf->eof) {
        result->eof = 1;
        return 1;
    }
    return 0;  /* Would block */
}

void h3_buffer_consume(h3_stream_buffer_t *buf, size_t bytes) {
    size_t old_consumed = buf->consumed_bytes;

    /* CRITICAL: Never consume more than what's available in the buffer.
     * The caller may pass ndatalen which includes HTTP/3 framing (HEADERS, etc.)
     * but our buffer only contains body data. Only consume actual body bytes.
     */
    size_t available = (buf->total_len > buf->consumed_bytes) ?
                       (buf->total_len - buf->consumed_bytes) : 0;
    size_t actual_consume = (bytes > available) ? available : bytes;

    if (actual_consume != bytes && H3_BUFFER_DEBUG) {
        fprintf(stderr, "h3_buffer_consume: CLAMPED request=%zu to available=%zu (total=%zu consumed=%zu)\n",
                bytes, actual_consume, buf->total_len, buf->consumed_bytes);
    }

    buf->consumed_bytes += actual_consume;

    if (H3_BUFFER_DEBUG && actual_consume > 0) {
        fprintf(stderr, "h3_buffer_consume: bytes=%zu consumed_before=%zu consumed_now=%zu total=%zu\n",
                actual_consume, old_consumed, buf->consumed_bytes, buf->total_len);
    }
}

/*
 * ACK handling
 */

void h3_buffer_ack(h3_stream_buffer_t *buf, size_t bytes) {
    buf->acked_bytes += bytes;

    if (H3_BUFFER_DEBUG) {
        fprintf(stderr, "h3_buffer_ack: bytes=%zu acked_now=%zu consumed=%zu\n",
                bytes, buf->acked_bytes, buf->consumed_bytes);
    }

    /* Diagnostic: acked should never exceed consumed */
    if (buf->acked_bytes > buf->consumed_bytes) {
        fprintf(stderr, "WARNING h3_buffer_ack: acked(%zu) > consumed(%zu)!\n",
                buf->acked_bytes, buf->consumed_bytes);
    }
}

void h3_buffer_flush_acked(h3_stream_buffer_t *buf) {
    /* Free chunks where ALL bytes have been acknowledged.
     * A chunk can be freed when: freed_bytes + chunk->len <= acked_bytes
     *
     * CRITICAL: Never free the write_chunk - it's still receiving data
     * and its len will grow. Freeing it would corrupt data being written.
     */
    while (buf->chunks && buf->chunks != buf->write_chunk &&
           (buf->freed_bytes + buf->chunks->len <= buf->acked_bytes)) {
        h3_data_chunk_t *chunk = buf->chunks;
        size_t chunk_len = chunk->len;

        buf->freed_bytes += chunk_len;
        buf->chunks = chunk->next;

        if (H3_BUFFER_DEBUG) {
            fprintf(stderr, "h3_buffer_flush_acked: freed chunk of %zu bytes, freed_bytes=%zu acked=%zu\n",
                    chunk_len, buf->freed_bytes, buf->acked_bytes);
        }

        free(chunk);
    }
}

/*
 * Query functions
 */

size_t h3_buffer_pending(h3_stream_buffer_t *buf) {
    if (buf->total_len > buf->consumed_bytes) {
        return buf->total_len - buf->consumed_bytes;
    }
    return 0;
}

size_t h3_buffer_in_flight(h3_stream_buffer_t *buf) {
    if (buf->consumed_bytes > buf->acked_bytes) {
        return buf->consumed_bytes - buf->acked_bytes;
    }
    return 0;
}

size_t h3_buffer_total(h3_stream_buffer_t *buf) {
    return buf->total_len;
}

size_t h3_buffer_memory_usage(h3_stream_buffer_t *buf) {
    /* Memory in use = total written minus what's been freed */
    if (buf->total_len > buf->freed_bytes) {
        return buf->total_len - buf->freed_bytes;
    }
    return 0;
}

int h3_buffer_can_write(h3_stream_buffer_t *buf, size_t len) {
    size_t current_usage = h3_buffer_memory_usage(buf);
    size_t new_usage = current_usage + len;

    if (new_usage > H3_MAX_BUFFER_SIZE) {
        if (H3_BUFFER_DEBUG) {
            fprintf(stderr, "h3_buffer_can_write: BACKPRESSURE current=%zu + new=%zu = %zu > max=%d\n",
                    current_usage, len, new_usage, H3_MAX_BUFFER_SIZE);
        }
        return 0;  /* Would exceed limit */
    }
    return 1;  /* OK to write */
}
