@echo off
echo This is a very dump script to generate a PPD/PPM file pair
echo for ActiveState Perl

perl Makefile.PL
nmake
tar cvf PageCamel.tar blib
gzip --best PageCamel.tar
nmake ppd
notepad PageCamel.ppd

