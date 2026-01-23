/*
 * h3_buffer.h - Chunk-based buffer structures for HTTP/3 response bodies
 *
 * CRITICAL: nghttp3 caches pointers returned from the read_data callback
 * until acked_stream_data is called. We CANNOT realloc buffers while nghttp3
 * holds pointers. This implementation uses fixed-size chunks that are only
 * freed after being fully acknowledged.
 */

#ifndef H3_BUFFER_H
#define H3_BUFFER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Chunk size - 64KB per chunk */
#define H3_CHUNK_SIZE 65536

/* Maximum buffer size - 10MB per stream for backpressure */
#define H3_MAX_BUFFER_SIZE (10 * 1024 * 1024)

/*
 * Individual data chunk - NEVER reallocated once created.
 * This ensures pointer stability for nghttp3's cached pointers.
 */
typedef struct h3_data_chunk {
    uint8_t data[H3_CHUNK_SIZE];
    size_t len;                      /* Bytes used in this chunk (0 to H3_CHUNK_SIZE) */
    struct h3_data_chunk *next;
} h3_data_chunk_t;

/*
 * Per-stream buffer tracking using chunk list.
 *
 * All byte counts are ABSOLUTE positions from stream start, not relative
 * to current chunks. This makes offset calculations simple and correct
 * even as chunks are freed.
 *
 * Invariant: freed_bytes <= acked_bytes <= consumed_bytes <= total_len
 *
 * - total_len: Total bytes ever written to this buffer (monotonically increasing)
 * - consumed_bytes: Bytes returned via read_data callback (nghttp3 has seen them)
 * - acked_bytes: Bytes acknowledged via acked_stream_data (safe to free)
 * - freed_bytes: Bytes freed from head of chunk list (memory released)
 */
typedef struct h3_stream_buffer {
    h3_data_chunk_t *chunks;         /* Head of chunk list (first non-freed chunk) */
    h3_data_chunk_t *write_chunk;    /* Current chunk being written to (tail) */

    size_t total_len;                /* Total bytes ever written (absolute) */
    size_t consumed_bytes;           /* Bytes returned via read_data (absolute) */
    size_t acked_bytes;              /* Bytes acknowledged (absolute) */
    size_t freed_bytes;              /* Bytes freed from head (absolute) */

    int eof;                         /* Set when all data has been queued */
} h3_stream_buffer_t;

/*
 * Buffer management functions
 */

/* Initialize a stream buffer */
void h3_buffer_init(h3_stream_buffer_t *buf);

/* Free all resources in a stream buffer */
void h3_buffer_cleanup(h3_stream_buffer_t *buf);

/* Append data to a stream buffer
 * Returns: 0 on success, -1 on memory allocation failure
 * Data is copied into chunk buffers.
 */
int h3_buffer_write(h3_stream_buffer_t *buf, const uint8_t *data, size_t len);

/* Mark buffer as EOF (no more data will be written) */
void h3_buffer_set_eof(h3_stream_buffer_t *buf);

/* Check if buffer has EOF set */
int h3_buffer_is_eof(h3_stream_buffer_t *buf);

/*
 * Read interface for nghttp3's read_data callback
 */

/* Result structure for read operations */
typedef struct {
    uint8_t *base;   /* Pointer into chunk buffer (stable, never reallocated) */
    size_t len;      /* Available bytes */
    int eof;         /* Set if this is the last data and EOF */
} h3_buffer_read_result_t;

/* Get data to read (for nghttp3 read_data callback)
 * Returns pointer and length of available data starting from consumed_bytes.
 * Returns data from ONE chunk only to simplify pointer lifetime.
 *
 * Returns: 1 if data available, 0 if would block, -1 on error
 */
int h3_buffer_read(h3_stream_buffer_t *buf, h3_buffer_read_result_t *result);

/* Advance consumed_bytes after data is confirmed written to QUIC
 * Call this from Perl after data is successfully written.
 */
void h3_buffer_consume(h3_stream_buffer_t *buf, size_t bytes);

/*
 * ACK handling
 */

/* Record that bytes have been acknowledged
 * Does NOT free memory - that's done in flush_acked.
 */
void h3_buffer_ack(h3_stream_buffer_t *buf, size_t bytes);

/* Free chunks that have been fully acknowledged
 * CRITICAL: Only call this at a safe point, NOT during writev_stream loop.
 * nghttp3 may still have cached pointers from read_data.
 */
void h3_buffer_flush_acked(h3_stream_buffer_t *buf);

/*
 * Query functions
 */

/* Get number of bytes buffered but not yet consumed */
size_t h3_buffer_pending(h3_stream_buffer_t *buf);

/* Get number of bytes consumed but not yet acknowledged */
size_t h3_buffer_in_flight(h3_stream_buffer_t *buf);

/* Get total bytes ever written */
size_t h3_buffer_total(h3_stream_buffer_t *buf);

/* Check if buffer can accept more data (backpressure check)
 * Returns: 1 if can accept, 0 if would exceed H3_MAX_BUFFER_SIZE
 */
int h3_buffer_can_write(h3_stream_buffer_t *buf, size_t len);

/* Get current memory usage (total_len - freed_bytes) */
size_t h3_buffer_memory_usage(h3_stream_buffer_t *buf);

#ifdef __cplusplus
}
#endif

#endif /* H3_BUFFER_H */
