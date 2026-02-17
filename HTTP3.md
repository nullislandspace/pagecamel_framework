# HTTP/3 Support

HTTP/3 support requires the ngtcp2 (QUIC) and nghttp3 (HTTP/3) C libraries,
plus GnuTLS for TLS 1.3.

## Option 1: System Packages (may be too old)

On Ubuntu/Debian:

    sudo apt install libnghttp3-dev libngtcp2-dev libngtcp2-crypto-gnutls-dev libgnutls28-dev

Ubuntu 24.04 ships ngtcp2 0.12.1 and nghttp3 0.8.0, which are too old for
this framework. If `perl Makefile.PL` reports that the libraries were not
found or the build fails, you need to install from source (Option 2).

## Option 2: Building from Source (Ubuntu 24.04)

### Prerequisites

Install the build tools and GnuTLS development headers:

    sudo apt install build-essential pkg-config libgnutls28-dev

### Set up a build directory

    mkdir -p ~/src/http3libs
    cd ~/src/http3libs

### Build and install nghttp3

nghttp3 has no external dependencies beyond a C compiler.
Build and install it first so that ngtcp2 can find it during its configure
step.

Check https://github.com/ngtcp2/nghttp3/releases for the latest version
and adjust the version number below accordingly.

    cd ~/src/http3libs
    wget https://github.com/ngtcp2/nghttp3/releases/download/v1.15.0/nghttp3-1.15.0.tar.gz
    tar xzf nghttp3-1.15.0.tar.gz
    cd nghttp3-1.15.0

    ./configure --prefix=/usr/local --enable-lib-only
    make -j$(nproc)
    sudo make install

### Build and install ngtcp2

ngtcp2 supports multiple TLS backends. We use GnuTLS (the `libgnutls28-dev`
package installed above). The `--with-gnutls` flag builds the
`ngtcp2_crypto_gnutls` helper library that the framework links against.

The `--without-openssl` flag is needed because Ubuntu 24.04's OpenSSL
does not have QUIC support, and ngtcp2 enables the OpenSSL backend by
default.

Check https://github.com/ngtcp2/ngtcp2/releases for the latest version
and adjust the version number below accordingly.

    cd ~/src/http3libs
    wget https://github.com/ngtcp2/ngtcp2/releases/download/v1.20.0/ngtcp2-1.20.0.tar.gz
    tar xzf ngtcp2-1.20.0.tar.gz
    cd ngtcp2-1.20.0

    ./configure --prefix=/usr/local --enable-lib-only --with-gnutls --without-openssl
    make -j$(nproc)
    sudo make install

### Update the linker cache

    sudo ldconfig

### Verify installation

    pkg-config --modversion libngtcp2 libngtcp2_crypto_gnutls libnghttp3

This should print three version numbers (e.g. 1.20.0, 1.20.0, 1.15.0).

## Building the Framework with HTTP/3

After the libraries are installed, rebuild the framework:

    cd /path/to/pagecamel_framework
    make clean
    perl Makefile.PL
    make

`perl Makefile.PL` will report whether the HTTP/3 libraries were detected.
If they were, the C/XS code in `lib/PageCamel/Protocol/HTTP3/` is compiled
and HTTP/3 support is available at runtime.

If the libraries are not installed, the framework builds and runs normally
with HTTP/1.1 and HTTP/2 only.
