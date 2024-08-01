wget https://cavac.at/public/pimenu/download/Net-CUPS2-0.65.tar.gz &&
wget https://cavac.at/public/pimenu/download/Image-Imlib2-2.04.tar.gz &&
tar xvzf Net-CUPS2-0.65.tar.gz &&
tar xvzf Image-Imlib2-2.04.tar.gz &&
cd Net-CUPS2-0.65 &&
perl Makefile.PL &&
make test install distclean &&
cd .. &&
cd Image-Imlib2-2.04 &&
perl Build.PL &&
./Build &&
./Build test &&
./Build install &&
./Build distclean &&
cd .. &&
rm -rf Net-CUPS2-0.65.tar.gz Net-CUPS2-0.65 Image-Imlib2-2.04.tar.gz Image-Imlib2-2.04 &&
echo DONE
