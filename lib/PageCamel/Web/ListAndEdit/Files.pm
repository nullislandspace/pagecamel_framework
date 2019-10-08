package PageCamel::Web::ListAndEdit::Files;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.3;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---



use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile writeBinFile slurpBinFilehandle);
use File::Basename;
use PageCamel::Helpers::DataBlobs;
use MIME::Base64;
use JSON::XS;
use PageCamel::Helpers::Strings qw(stripString splitStringWithQuotes humanFilesize);
use PageCamel::Helpers::URI qw[decode_uri_path];

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{orderby})) {
        croak("orderby must be defined in " . $self->{modname});
    }

    return $self;
}

sub register {
    my $self = shift;

    $self->register_webpath($self->{download}->{webpath} . '/download', "get_download", 'GET');

    $self->register_webpath($self->{manage}->{webpath}, "get_manage", 'GET', 'POST');

    $self->register_webpath($self->{checkfname}->{webpath}, "get_fname", 'POST');

    $self->register_webpath($self->{selecttable}->{webpath}, "get_lines", 'POST');

    return;
}

sub clean_fname {
    my ($self, $filename) = @_;

    my $safe_filename_characters = "a-zA-Z0-9_.-";
    $filename =~ s/\\/\//go;
    my ( $name, $path, $extension ) = fileparse ( $filename, '\..*' );
    $filename = $name . $extension;
    $filename =~ tr/ /_/;
    $filename =~ s/[^$safe_filename_characters]//g;
    return $filename;
}

sub get_manage {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};

    my $mode = $ua->{postparams}->{'mode'} || 'view';
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    if($mode eq "delete") {
        my $delsth = $dbh->prepare_cached("DELETE FROM " . $self->{tablename} . " WHERE filename = ?")
                or croak($dbh->errstr);
        my @delfiles;
        if(ref $ua->{postparams}->{'delfile'} eq 'ARRAY') {
            @delfiles = @{$ua->{postparams}->{'delfile'}};
        } elsif(defined($ua->{postparams}->{'delfile'})) {
            push @delfiles, $ua->{postparams}->{'delfile'};
        }
        foreach my $delfile (@delfiles) {
            next if($delfile eq '');
            $delsth->execute($delfile) or $dbh->errstr;
        }
        $dbh->commit;
    } elsif($mode eq "upload") {
        # Make filename safe(r)

        my $realfname = $ua->{postparams}->{"upfile"} || '';
        my $filename = $ua->{postparams}->{"upfname"} || '';
        my $description = $ua->{postparams}->{"description"};
        $filename = $self->clean_fname($filename);

        # Now, handle the upload data
        #my $fh = $ua->upload("filename");

        if($filename ne '' && $realfname ne '' && defined($ua->{files}->{$realfname}->{data})) {
            # First delete the existing file (if there is one)
            my $delsth = $dbh->prepare_cached("DELETE FROM " . $self->{tablename} . " WHERE filename = ?")
                    or croak($dbh->errstr);
            $delsth->execute($filename) or croak($dbh->errstr);

            my $blob = PageCamel::Helpers::DataBlobs->new($dbh);
            $blob->blobOpen();
            my $data = $ua->{files}->{$realfname}->{data};
            $blob->blobWrite(\$data);
            my $filesize = $blob->getLength();
            my $blobid = $blob->blobID();
            $blob->blobClose();


            my $insth = $dbh->prepare("INSERT INTO " . $self->{tablename} . " (filename, filesize_bytes, description, file_datablob_id)
                                      VALUES (?,?,?,?)")
                    or croak($dbh->errstr);
            $insth->execute($filename, $filesize, $description, $blobid)
                    or croak($dbh->errstr);
            $dbh->commit;

        }
    }

    my @files;
    my $selsth = $dbh->prepare_cached("SELECT * FROM " . $self->{tablename} . " ORDER BY filename")
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);
    while((my $file = $selsth->fetchrow_hashref)) {
        $file->{url} = $self->{download}->{webpath} . '/download/' . $file->{filename};
        push @files, $file;
    }


    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{manage}->{pagetitle},
        webpath         =>  $self->{manage}->{webpath},
        downwebpath     =>  $self->{download}->{webpath},
        checkfname      =>  $self->{checkfname}->{webpath},
        AvailFiles  =>  \@files,
    );

    my $template = $self->{server}->{modules}->{templates}->get("listandedit/files", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_download {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $filename = $ua->{url};
    my $remove = $self->{download}->{webpath} . "/download/";
    $filename =~ s/^$remove//;

    my $blobid;
    my $selsth = $dbh->prepare("SELECT *
                               FROM " . $self->{tablename} . "
                               WHERE filename = ?")
            or croak($dbh->errstr);
    $selsth->execute($filename);
    while((my $file = $selsth->fetchrow_hashref)) {
        $blobid = $file->{file_datablob_id};
    }
    return (status => 404) unless defined($blobid);

    my $blob = PageCamel::Helpers::DataBlobs->new($dbh, $blobid);
                $blob->blobOpen();
    my $data;
    $blob->blobRead(\$data);
    $blob->blobClose();


    return (status  =>  404) unless defined($data);
    return (status  =>  200,
            type    => "application/octet-stream",
            "Content-Disposition" => "attachment; filename=\"$filename\";",
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            data    => $data);
}


sub get_fname {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $filename = $ua->{postparams}->{'fname'} || '';
    $filename = $self->clean_fname($filename);

    my %data = (
        fname   => $filename,
        status  => 'OK',
        statustext => 'OK',
        description => '',
    );

    # Check for existing filename
    my $selsth = $dbh->prepare_cached("SELECT *
                                      FROM " . $self->{tablename} . "
                                      WHERE filename = ?
                                      LIMIT 1")
            or croak($dbh->errstr);
    $selsth->execute($filename) or croak($dbh->errstr);
    my $existcount = 0;
    while((my $line = $selsth->fetchrow_hashref)) {
        $existcount++;
        $data{description} = $line->{description};
    }

    if($existcount) {
        $data{status} = 'WARNING';
        $data{statustext} = "File exists, will overwrite!<br/><b>This may lead to caching problems for the next few hours!</b>";
    }

    my $jsondata = encode_json \%data;

    return (status  =>  200,
            type    => "text/plain",
            data    => $jsondata);
}

sub get_lines {
    my ($self, $ua) = @_;


    my $dbh = $self->{server}->{modules}->{$self->{db}};
    #my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $method = $ua->{method};


    my $limit = $ua->{postparams}->{'length'} || 10;
    my $offset = $ua->{postparams}->{'start'} || 0;

    my $webpath = $ua->{url};
    my $urlid = '';
    if($self->{use_urlid}) {
        $urlid = $webpath;
        $urlid =~ s/^$self->{webpath}\///;
        $urlid = decode_uri_path($urlid);
    }


    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
    );

    my $userlang = $webdata{UserLanguage} || "eng";

    my %params = %{$ua->{postparams}};
    my $where = '';


    my $search = $ua->{postparams}->{'search[value]'} || '';
    #print STDERR "    Filter: $search\n";
    if($search ne '') {
        my @searchparts = splitStringWithQuotes(lc $search);

        foreach my $sp (@searchparts)  {
            $sp = stripString($sp);
            my $negate = 0;
            if($sp =~ /^\!/) {
                $negate = 1;
                $sp =~ s/^\!//;
            }
            $sp = stripString($sp);
            next if($sp eq '');

            $sp = $dbh->quote($sp);
            # Insert the percent signs
            $sp =~ s/^\'/\'%/;
            $sp =~ s/\'$/%\'/;

            if($where ne '') {
                $where .= ' AND ';
            }

            my @subclauses;

            if(!$negate) {
                foreach my $col (qw[filename description]) {
                    my $subclause = $col . "::text ILIKE $sp";
                    push @subclauses, $subclause;
                }
                $where .= ' ( ' . join(' OR ', @subclauses) . ' ) ';
            } else {
                foreach my $col (qw[filename description]) {
                    my $subclause = $col . "::text NOT ILIKE $sp";
                    push @subclauses, $subclause;
                }
                $where .= ' ' . join(' AND ', @subclauses) . ' ';
            }

        }

    }

    if($where ne '') {
        $where = "WHERE $where ";
    }

    my $orderby = $self->{orderby};
    my @orderjs;
    my @listcolumns = qw[filename filename description filesize_bytes];
    if(defined($ua->{postparams}->{'order[0][dir]'})) {
        my $sortcount = 0;
        while(1) {
            last if(!defined($ua->{postparams}->{'order[' . ($sortcount + 1) . '][dir]'}));
            $sortcount++;
        }
        my @sortcols;
        for(my $i = 0; $i <= $sortcount; $i++) {
            my $sortnum = $ua->{postparams}->{'order[' . $i . '][column]'} || 0;
            my $sort = $listcolumns[$sortnum];
            my $dir = $ua->{postparams}->{'order[' . $i . '][dir]'} || 'asc';
            if($dir !~ /asc/i) {
                $sort .= ' DESC';
                push @orderjs, '[' . $sortnum . ",'desc']" ;
            } else {
                push @orderjs, '[' . $sortnum . ",'asc']" ;
            }
            push @sortcols, $sort;
        }

        if(@sortcols) {
            $orderby = join(', ', @sortcols);
        }
    }
    
    if($orderby eq '') {
        $orderby = $self->{orderby};
    }

    my $tcountsth = $dbh->prepare_cached("SELECT count(*) FROM " . $self->{tablename})
                or croak($dbh->errstr);
    $tcountsth->execute or croak($dbh->errstr);
    my ($tcount) = $tcountsth->fetchrow_array;
    $tcountsth->finish;
    if(!defined($tcount)) {
        $tcount = 0;
    }


    {
        my @columns;
        my $colcount = 0;
        foreach my $item (qw[Preview Filename Description Size]) {
            my %column = (
                header  => $item,
            );
            push @columns, \%column;
            $colcount++;
        }
        $webdata{columns} = \@columns;
        $webdata{column_count} = $colcount;
    }

    my @pkparts;
    foreach my $pkitem (qw[filename]) {
        push @pkparts, $pkitem;
    }

    my $selstmt = "SELECT " . join(', ', qw[filename description filesize_bytes]) .
                    ", count(*) OVER () as whereclause_totalcount " .
                    " FROM " . $self->{tablename} . 
                    " $where " .
                    " ORDER BY $orderby" .
                    " LIMIT $limit OFFSET $offset ";


    my $selsth = $dbh->prepare($selstmt) or croak($dbh->errstr);

    my $fcount = 0;
    my @lines;
    $selsth->execute or croak($dbh->errstr);
    while((my $rawline = $selsth->fetchrow_hashref)) {
        my @columns;
        $fcount = $rawline->{whereclause_totalcount};
        my $readableSize = humanFilesize($rawline->{filesize_bytes});
        my $destpath = $self->{download}->{webpath} . '/download/' . $rawline->{filename};

        push @columns, $rawline->{filename} . '<br/>' .
                        '<a href="#" onclick="return selectFile(' . "'" . $destpath . "', " .
                                                                    "'" . $rawline->{description} . "'," .
                                                                    "'" . $rawline->{filesize_bytes} . "'," .
                                                                    "'" . $readableSize . "'" .
                        ');">' .
                        $destpath .
                        '</a>';
        my @splitdesc = split//, $rawline->{description};
        my $splitlinedesc = '';
        my $splitpart = '';
        while(@splitdesc) {
            my $char = shift @splitdesc;
            if($char eq ' ' && length($splitpart) > 15) {
                $splitlinedesc .= $splitpart . '<br/>';
                $splitpart = '';
                next;
            }
            $splitpart .= $char;
            if(length($splitpart) > 25) {
                $splitlinedesc .= $splitpart . '<br/>';
                $splitpart = '';
            }
        }
        $splitlinedesc .= $splitpart;
        push @columns, $splitlinedesc;
        push @columns, $readableSize;

        push @lines, \@columns;
    }
    $selsth->finish;
    $dbh->rollback;
    $webdata{aaData} = \@lines;

    $webdata{sEcho} = $ua->{postparams}->{'sEcho'} || '__0__';
    if($tcount < $fcount) {
        $tcount = $fcount;
    }
    $webdata{iTotalRecords} = $tcount;
    $webdata{iTotalDisplayRecords} = $fcount;

    my $jsondata = encode_json \%webdata;

    return (status  =>  200,
            type    => "application/json",
            data    => $jsondata);
}


1;
__END__

=head1 NAME

PageCamel::Web::Blog::Files - manage downloadable files for the blog.

=head1 SYNOPSIS

  use PageCamel::Web::Blog::Files;

=head1 DESCRIPTION

Webmask and APIs to managne downloadable files for the blog.

=head2 new

Create a new instance.

=head2 register

Register the callbacks.

=head2 clean_fname

Sanitize a filename.

=head2 get_manage

Manage the files.

=head2 get_download

Download a file

=head2 get_fname

AJAX callback to check if a file already exists.

=head2 get_lines

Get the lines for the datatables list.

=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
