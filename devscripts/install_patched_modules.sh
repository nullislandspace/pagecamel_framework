wget https://cavac.at/public/pimenu/download/Net-CUPS2-0.65.tar.gz &&
wget https://cavac.at/public/pimenu/download/Image-Imlib2-2.04.tar.gz &&
wget https://cavac.at/public/pimenu/download/Acme-Damn-0.09.tar.gz &&
wget https://cavac.at/public/pimenu/download/Crypt-OpenSSL-RSA-0.99.tar.gz &&
tar xvzf Net-CUPS2-0.65.tar.gz &&
tar xvzf Image-Imlib2-2.04.tar.gz &&
tar xvzf Acme-Damn-0.09.tar.gz &&
tar xvzf Crypt-OpenSSL-RSA-0.99.tar.gz &&
cd Net-CUPS2-0.65 &&
cpan .
cd .. &&
cd Image-Imlib2-2.04 &&
cpan .
cd .. &&
cd Acme-Damn-0.09 &&
cpan .
cd .. &&
cd Crypt-OpenSSL-RSA-0.99 &&
cpan .
cd .. &&
rm -rf Net-CUPS2-0.65.tar.gz Net-CUPS2-0.65 Image-Imlib2-2.04.tar.gz Image-Imlib2-2.04 Acme-Damn-0.09.tar.gz Acme-Damn-0.09 Crypt-OpenSSL-RSA-0.99.tar.gz Crypt-OpenSSL-RSA-0.99 &&
echo DONE
