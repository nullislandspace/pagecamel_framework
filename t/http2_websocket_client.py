#!/usr/bin/env python3
"""
RFC 8441 WebSocket over HTTP/2 test client.
Tests extended CONNECT method for WebSocket bootstrapping.

Requirements:
    pip install h2

Usage:
    python3 http2_websocket_client.py
"""

import socket
import ssl
import struct
import os
import sys

try:
    import h2.connection
    import h2.config
    import h2.events
except ImportError:
    print("Please install h2: pip install h2")
    sys.exit(1)

HOST = 'cavac.at'
PORT = 443
WS_PATH = '/guest/kaffeesim/ws'


def create_ssl_connection(host, port):
    """Create TLS connection with ALPN for HTTP/2."""
    ctx = ssl.create_default_context()
    ctx.set_alpn_protocols(['h2'])

    sock = socket.create_connection((host, port))
    tls_sock = ctx.wrap_socket(sock, server_hostname=host)

    # Verify ALPN negotiated h2
    negotiated = tls_sock.selected_alpn_protocol()
    print(f"[*] Connected to {host}:{port}")
    print(f"[*] ALPN negotiated: {negotiated}")

    if negotiated != 'h2':
        print("[!] Server did not negotiate HTTP/2!")
        sys.exit(1)

    return tls_sock


def send_data(sock, conn):
    """Send pending HTTP/2 data."""
    data = conn.data_to_send()
    if data:
        sock.sendall(data)


def receive_data(sock, conn):
    """Receive and process HTTP/2 data."""
    data = sock.recv(65535)
    if not data:
        return []
    events = conn.receive_data(data)
    return events


def main():
    print("=" * 60)
    print("RFC 8441 WebSocket over HTTP/2 Test Client")
    print("=" * 60)
    print()

    # Connect with TLS + ALPN
    sock = create_ssl_connection(HOST, PORT)
    sock.settimeout(10)

    # Create HTTP/2 connection (client side)
    config = h2.config.H2Configuration(client_side=True)
    conn = h2.connection.H2Connection(config=config)

    # Initiate HTTP/2 connection
    conn.initiate_connection()
    send_data(sock, conn)

    # Receive server settings
    print("[*] Waiting for server SETTINGS...")
    events = receive_data(sock, conn)
    send_data(sock, conn)  # Send SETTINGS ACK

    # Check if server supports extended CONNECT (SETTINGS_ENABLE_CONNECT_PROTOCOL)
    enable_connect = False
    for event in events:
        if isinstance(event, h2.events.RemoteSettingsChanged):
            settings = event.changed_settings
            print(f"[*] Server settings: {settings}")
            # SETTINGS_ENABLE_CONNECT_PROTOCOL = 0x8
            if 0x8 in settings:
                enable_connect = settings[0x8].new_value == 1
                print(f"[*] ENABLE_CONNECT_PROTOCOL: {enable_connect}")

    if not enable_connect:
        print("[!] Server does not advertise ENABLE_CONNECT_PROTOCOL!")
        print("[!] Extended CONNECT (RFC 8441) may not be supported.")
        # Continue anyway to see what happens

    # Send extended CONNECT request for WebSocket
    print()
    print(f"[*] Sending extended CONNECT for WebSocket: wss://{HOST}{WS_PATH}")

    # RFC 8441 extended CONNECT headers
    headers = [
        (':method', 'CONNECT'),
        (':protocol', 'websocket'),
        (':scheme', 'https'),
        (':authority', HOST),
        (':path', WS_PATH),
        ('sec-websocket-version', '13'),
        ('sec-websocket-protocol', 'chat'),
        ('origin', f'https://{HOST}'),
    ]

    stream_id = conn.get_next_available_stream_id()
    print(f"[*] Using stream ID: {stream_id}")

    try:
        conn.send_headers(stream_id, headers, end_stream=False)
        send_data(sock, conn)
    except Exception as e:
        print(f"[!] Error sending headers: {e}")
        sock.close()
        return

    # Receive response
    print("[*] Waiting for response...")

    response_headers = None
    websocket_data = []

    try:
        for _ in range(50):  # Max iterations
            events = receive_data(sock, conn)
            send_data(sock, conn)

            for event in events:
                print(f"[*] Event: {type(event).__name__}")

                if isinstance(event, h2.events.ResponseReceived):
                    response_headers = dict(event.headers)
                    status = response_headers.get(':status', 'unknown')
                    print(f"[*] Response status: {status}")
                    print(f"[*] Response headers: {response_headers}")

                    if status == '200':
                        print("[+] SUCCESS! WebSocket tunnel established over HTTP/2!")
                    else:
                        print(f"[!] Unexpected status: {status}")

                elif isinstance(event, h2.events.DataReceived):
                    data = event.data
                    print(f"[*] Received {len(data)} bytes of tunnel data")
                    websocket_data.append(data)

                    # Acknowledge the data
                    conn.acknowledge_received_data(len(data), event.stream_id)
                    send_data(sock, conn)

                    # Try to parse as WebSocket frame
                    parse_websocket_frames(data)

                elif isinstance(event, h2.events.StreamEnded):
                    print(f"[*] Stream {event.stream_id} ended")
                    break

                elif isinstance(event, h2.events.StreamReset):
                    print(f"[!] Stream reset: error_code={event.error_code}")
                    break

                elif isinstance(event, h2.events.ConnectionTerminated):
                    print(f"[!] Connection terminated: {event}")
                    break

            if websocket_data:
                # We got some data, might be enough for a test
                if len(websocket_data) >= 2:
                    break

    except socket.timeout:
        print("[*] Socket timeout (this may be normal if no messages)")
    except Exception as e:
        print(f"[!] Error: {e}")

    print()
    print("=" * 60)
    print("Test completed")
    print(f"Total WebSocket data chunks received: {len(websocket_data)}")
    print("=" * 60)

    sock.close()


def parse_websocket_frames(data):
    """Try to parse WebSocket frames from tunnel data."""
    if len(data) < 2:
        return

    try:
        # WebSocket frame format:
        # byte 0: FIN(1) RSV(3) OPCODE(4)
        # byte 1: MASK(1) PAYLOAD_LEN(7)
        byte0 = data[0]
        byte1 = data[1]

        fin = (byte0 >> 7) & 1
        opcode = byte0 & 0x0F
        masked = (byte1 >> 7) & 1
        payload_len = byte1 & 0x7F

        opcode_names = {
            0: 'continuation',
            1: 'text',
            2: 'binary',
            8: 'close',
            9: 'ping',
            10: 'pong',
        }

        print(f"    [WebSocket] FIN={fin} OPCODE={opcode_names.get(opcode, opcode)} "
              f"MASKED={masked} LEN={payload_len}")

        # Extract payload for text frames
        if opcode == 1 and payload_len < 126:
            offset = 2
            if masked:
                offset += 4  # Skip mask key
            if len(data) >= offset + payload_len:
                payload = data[offset:offset + payload_len]
                try:
                    text = payload.decode('utf-8')
                    print(f"    [WebSocket] Text: {text[:100]}{'...' if len(text) > 100 else ''}")
                except:
                    pass
    except Exception as e:
        print(f"    [WebSocket] Parse error: {e}")


if __name__ == '__main__':
    main()
