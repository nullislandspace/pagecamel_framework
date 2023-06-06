package PageCamel::Web::ListAndEdit::Main;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.2;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Padding qw(doFPad);
use PageCamel::Helpers::Strings qw(stripString splitStringWithQuotes);
use HTML::Entities;
use JSON::XS;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::URI qw[encode_uri encode_uri_path decode_uri_part decode_uri_path];
use PageCamel::Helpers::Translator;
use PageCamel::Helpers::Colors qw[colorHexMaxContrast colorHex2RGB colorSwatchHTML];
use MIME::Base64;
use Digest::SHA1  qw(sha1_hex);
use IO::Compress::Gzip qw(gzip $GzipError);
use PageCamel::Helpers::FileSlurp qw(writeBinFile);


sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{sessionname} = "ListView::" . $self->{modname};

    if(!defined($self->{support_mobile})) {
        $self->{support_mobile} = 0;
    }

    $self->{userawhtml} = 0;

    if(!defined($self->{use_urlid})) {
        $self->{use_urlid} = 0;
    }

    if(!defined($self->{display_length})) {
        $self->{display_length} = 10;
    }

    if(!defined($self->{showpagetitle})) {
        $self->{showpagetitle} = 0;
    }

    if(!defined($self->{listonly})) {
        $self->{listonly} = 0;
    }
    
    if(!defined($self->{listonly_customselect})) {
        $self->{listonly_customselect} = 0;
    }

    if(!defined($self->{editonly})) {
        $self->{editonly} = 0;
    }

    if(!defined($self->{listpageheader})) {
        $self->{listpageheader} = '';
    }

    if(!defined($self->{editpageheader})) {
        $self->{editpageheader} = '';
    }

    if(!defined($self->{mastertemplate})) {
        $self->{mastertemplate} = '';
    }

    if(defined($self->{list}) && !defined($self->{list}->{showads})) {
        if(defined($self->{showads})) {
            $self->{list}->{showads} = $self->{showads};
        } else {
            $self->{list}->{showads} = 0;
        }
    }
    if(defined($self->{edit}) && !defined($self->{edit}->{showads})) {
        if(defined($self->{showads})) {
            $self->{edit}->{showads} = $self->{showads};
        } else {
            $self->{edit}->{showads} = 0;
        }
    }

    if(defined($self->{list}) && !defined($self->{list}->{sidebarhtml})) {
        if(defined($self->{sidebarhtml})) {
            $self->{list}->{sidebarhtml} = $self->{sidebarhtml};
        } else {
            $self->{list}->{sidebarhtml} = '';
        }
    }
    if(defined($self->{edit}) && !defined($self->{edit}->{sidebarhtml})) {
        if(defined($self->{sidebarhtml})) {
            $self->{edit}->{sidebarhtml} = $self->{sidebarhtml};
        } else {
            $self->{edit}->{sidebarhtml} = '';
        }
    }

    $self->{useextraeditscript} = 0;
    if(defined($self->{editjavascript})) {
        $self->{useextraeditscript} = 1;
        my $extrajavascript = '';
        if(defined($self->{editjavascript}->{functions})) {
            $extrajavascript = $self->{editjavascript}->{functions} . "\n";
        }

        if(defined($self->{editjavascript}->{onload})) {

            $extrajavascript .= "function LaEExtraOnLoad() {\n" .
                                 $self->{editjavascript}->{onload} .
                                 "}\n";
        }
        $self->{extraeditscript} = $extrajavascript;
        $self->{extraeditscript_etag} = sha1_hex(getFileDate() . sha1_hex($extrajavascript));
        $self->{extraeditscript_webdate} = getWebdate();

        my $gzipped;
        if(gzip(\$extrajavascript => \$gzipped)) {
            if(length($gzipped) < length($extrajavascript)) {
                $self->{extraeditscript_gzip} = $gzipped;
            }
        }
    }

    $self->{useextralistscript} = 0;
    if(defined($self->{listjavascript})) {
        $self->{useextralistscript} = 1;
        my $extrajavascript = '';
        if(defined($self->{listjavascript}->{functions})) {
            $extrajavascript = $self->{listjavascript}->{functions} . "\n";
        }

        if(defined($self->{listjavascript}->{onload})) {

            $extrajavascript .= "function LaEExtraOnLoad() {\n" .
                                 $self->{listjavascript}->{onload} .
                                 "}\n";
        }
        $self->{extralistscript} = $extrajavascript;
        $self->{extralistscript_etag} = sha1_hex(getFileDate() . sha1_hex($extrajavascript));
        $self->{extralistscript_webdate} = getWebdate();

        my $gzipped;
        if(gzip(\$extrajavascript => \$gzipped)) {
            if(length($gzipped) < length($extrajavascript)) {
                $self->{extralistscript_gzip} = $gzipped;
            }
        }
    }


    return $self;
}


sub register($self) {

    $self->register_webpath($self->{webpath}, "get");
    return;
}

sub reload($self) {

    # Run sanity checks on configuration
    my $ok = 1;
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    foreach my $mustattr (qw[orderby primarykey table webpath pagetitle db session]) {
        if(!defined($self->{$mustattr})) {
            print "    Attribute $mustattr not set!\n";
            $ok = 0;
        }
    }

    foreach my $mustnotattr (qw[memcache ajaxpath]) {
        if(defined($self->{$mustnotattr})) {
            print "    Attribute $mustnotattr is set but must not be!\n";
            $ok = 0;
        }
    }

    if($self->{listonly} && $self->{editonly}) {
        print "    Attributes 'listonly' and 'editonly' are mutually exclusive!\n";
        $ok = 0;
    }

    if(!$ok) {
        goto finishreload;
    }

    # ------------- LIST -------------
    if($self->{editonly}) {
        # Check if we are in listonly mode
        if(defined($self->{list})) {
            print "   LIST columns defined but module is in editonly mode\n";
            $ok = 0;
            goto finishreload;
        }
        # Jump to EDIT validation
        goto editonlymode;
    }
    my @listallowedtypes = qw[text textarray url boolean array date led html color colorswatch image];

    foreach my $optionalattr (qw[guess_stats column_filters send_csv download_csv quickselect]) {
        if(!defined($self->{$optionalattr})) {
            #print "    Attribute $optionalattr is undefined, set to 0\n";
            $self->{$optionalattr} = 0;
        }
    }

    foreach my $optionalattr (qw[radiobuttonhtml]) {
        if(!defined($self->{$optionalattr})) {
            print "    Attribute $optionalattr is undefined, set to empty string\n";
            $self->{$optionalattr} = '';
        }
    }

    if($self->{quickselect}) {
        if($self->{listonly}) {
            print "    Attribute quickselect not allowed in listonly mode!\n";
            $ok = 0;
        } elsif($self->{radiobuttonhtml} ne '') {
            print "    Attributes quickselect and radiobuttonhtml are mutually exclusive!\n";
            $ok = 0;
        }
    }


    # When send_csv is true, then we need a sendmail module
    if($self->{send_csv} && !defined($self->{sendmail})) {
        print "    Attribute send_csv is set to 1 but no sendmail module is configured!\n";
        $ok = 0;
    }

    if(!$ok) {
        goto finishreload;
    }

    if(defined($self->{filtercolumn})) {
        if($self->{filtercolumn} eq '') {
            print "    LIST: Filtercolumn is defined but empty!\n";
            $ok = 0;
        }
        my $type = $dbh->getColumnType($self->{table}, $self->{filtercolumn});
        if(!defined($type)) {
            print '    LIST: Filtercolumn ', $self->{filtercolumn}, ' of table ', $self->{table}, " does not exist!\n";
            $ok = 0;
        }elsif($type ne 'text') {
            print "    LIST: Filtercolumn is not of type 'text'!\n";
            $ok = 0;
        }
    }

    my $pktype = ref($self->{primarykey});
    if(!defined($pktype) || $pktype ne 'HASH' || !defined($self->{primarykey}->{item})) {
        print "    Primary key not defined as an item list\n";
        $ok = 0;
        goto finishreload;
    }

    my $pkcount = 0;
    foreach my $pkitem (@{$self->{primarykey}->{item}}) {
        if(!defined($pkitem->{column})) {
            print "    Primary key item does not define column\n";
            $ok = 0;
            next;
        }
        my $pkcol = $pkitem->{column};
        my $type = $dbh->getColumnType($self->{table}, $pkcol);
        if(!defined($type)) {
            print "    Primary key column $pkcol or table " . $self->{table} . " does not exist!\n";
            $ok = 0;
        }
        $pkcount++;
    }

    if(!$ok) {
        goto finishreload;
    }

    if($self->{useserial} && $pkcount > 1) {
        print "    Tables with useserial=1 only support a single primary key column but you used $pkcount!\n";
        $ok = 0;
        goto finishreload;
    }

    my @listcolumns;
    my @listcolumnsnameonly;
    my @wherecolumns;
    foreach my $item (@{$self->{list}->{item}}) {
        foreach my $required (qw[header column type]) {
            if(!defined($item->{$required})) {
                print "    LIST: Attribute \"$required\" not set!\n";
                $ok = 0;
                next;
            }
        }

        if(!contains($item->{type}, \@listallowedtypes)) {
                print "    LIST: type $item->{type} not supported!\n";
                $ok = 0;
        }

        if($item->{type} eq 'html') {
            $self->{userawhtml} = 1;
        }

        if($item->{type} eq 'url') {
            if(!defined($item->{urlformat}) || $item->{urlformat} eq '') {
                print "    LIST: Attribute \"urlformat\" not set for $item->{column}!\n";
                $ok = 0
            }
            if(!defined($item->{encodeslashes})) {
                #print "    LIST: Attribute \"encodeslashes\" not set for $item->{column}, defaulting to 0\n";
                $item->{encodeslashes} = 0;
            }
        }

        if($item->{type} eq 'text' && !defined($item->{length})) {
            #print "    LIST: Type \"text\" does not define 'length', disabling display limit for column $item->{column}\n";
            $item->{length} = 0;
        }

        if(defined($item->{columnscript})) {
            push @listcolumns, '(' . $item->{columnscript} . ') AS ' . $item->{column};
            push @listcolumnsnameonly, $item->{column};
            push @wherecolumns, '(' . $item->{columnscript} . ')';
        } else {
            push @listcolumns, $item->{column};
            push @listcolumnsnameonly, $item->{column};
            push @wherecolumns, $item->{column};
        }

        my $type;
        if(defined($item->{columnscript})) {
            if(!defined($item->{columntype})) {
                print '    LIST: Columnscript for ', $item->{column}, ' of table ', $self->{table}, " requires columntype!\n";
                $ok = 0;
                next;
            }
           $type = $item->{columntype};
        } else {
            $type = $dbh->getColumnType($self->{table}, $item->{column});
        }

        if(!defined($type)) {
            print '    LIST: Column ', $item->{column}, ' of table ', $self->{table}, " does not exist!\n";
            $ok = 0;
            next;
        }

        my %listtesttypes = (
            array   => [qw[array]],
            boolean => [qw[led boolean]],
            numeric => [qw[textarray text url]],
            text    => [qw[textarray text url html boolean color colorswatch image]],
        );

        foreach my $testtype (keys %listtesttypes) {
            if($type eq $testtype && !contains($item->{type}, $listtesttypes{$testtype})) {
                print '    LIST: Column ', $item->{column}, ' of table ', $self->{table}, " type is $testtype but configured isn't any of (",
                        join(',',@{$listtesttypes{$testtype}}) , ")! but $item->{type}\n";
                $ok = 0;
                next;
            }
        }

    }
    $self->{listcolumns} = \@listcolumns;
    $self->{listcolumnsnameonly} = \@listcolumnsnameonly;
    $self->{wherecolumns} = \@wherecolumns;

    # Generate the defaultlastsort value
    {
        my @sortparts = split/\,/, $self->{orderby};
        my @sortcols;
        my $sortoffs = 0;
        if(!$self->{listonly} || $self->{listonly_customselect}) {
            $sortoffs = 1;
        }
        foreach my $sortpart (@sortparts) {
            $sortpart = stripString($sortpart);
            my ($colname, $sortorder) = split/\ +/, $sortpart;

            # parse sortorder
            if(!defined($sortorder)) {
                $sortorder = '';
            }
            $sortorder = lc $sortorder || '';
            if($sortorder ne 'desc') {
                $sortorder = 'asc';
            }
            my $colnum = -1;
            for(my $i = 0; $i < scalar @{$self->{listcolumns}}; $i++) {
                if($self->{listcolumns}->[$i] eq $colname) {
                    $colnum = $i;
                    last;
                }
            }
            if($colnum == -1) {
                print "    Column $colname in orderby not in listcolumns\n";
                $ok = 0;
                next;
            }
            $colnum += $sortoffs;
            push @sortcols, [$colnum, $sortorder];
        }
        my $defaultlastsort = encode_json \@sortcols;

        $self->{defaultlastsort} = $defaultlastsort;

    }
    
    # ------------- EDIT -------------
    editonlymode:
    if($self->{listonly}) {
        # Check if we are in listonly mode
        if(defined($self->{edit})) {
            print "   EDIT columns defined but module is in listonly mode\n";
            $ok = 0;
        }
        goto finishreload;
    }

    foreach my $mustattr (qw[candelete cancreate useserial]) {
        if(!defined($self->{$mustattr})) {
            print "    Attribute $mustattr not set!\n";
            $ok = 0;
        }
    }

    foreach my $optionalattr (qw[autosave cancopy cansaveandclose useprevnext generateauditlog]) {
        if(!defined($self->{$optionalattr})) {
            #print "    Attribute $optionalattr is undefined, set to 0\n";
            $self->{$optionalattr} = 0;
        }
    }
    
    if($self->{cancopy} && !$self->{useserial}) {
        print "    Attribute cancopy is true but useserial is not. Can only copy when using serial datatype for primary key!\n";
        $ok = 0
    }
    
    if($self->{cancopy} && !$self->{cancreate}) {
        print "    Attribute cancopy is true but cancreate is not. Can only copy when user is allowed to create new entries\n";
        $ok = 0
    }

    if(!defined($self->{extrattvars})) {
        $self->{extrattvars} = '';
    }

    $self->{editcolumns} = [];
    $self->{readonlycolumns} = [];
    $self->{editcolumntypes} = {};
    $self->{editcolumnnullable} = {};
    $self->{gotocolumns} = [];

    $self->{needcvceditor} = 0;
    $self->{needscripteditor} = 0;
    $self->{usetabs} = 0;


    $self->{tabstablenames} = [qw[MainDataTable HelperTable1 HelperTable2 HelperTable3 HelperTable4 HelperTable5 HelperTable6 HelperTable7]];

    $self->{editallowedtypes} = [qw[text textarray textarea textarea-readonly editor scripteditor number boolean array enum subenum enumarray switch led display codedisplay slider checkbox date dateonly timeonly hidden colorpicker image imagedisplay]];
    $self->{readonlytypes} = [qw[textarea-readonly led display codedisplay imagedisplay]];


    foreach my $item (@{$self->{edit}->{item}}) {
        if(!$self->validateEditItem($item, 0)) {
            $ok = 0;
        }
    }

    if(defined($self->{forceusercolumn})) {
        my $type = $dbh->getColumnType($self->{table}, $self->{forceusercolumn});
        if(!defined($type)) {
            print '    EDIT: Forceusercolumn ', $self->{forceusercolumn}, ' of table ', $self->{table}, " does not exist!\n";
            $ok = 0;
        } elsif($type ne 'text') {
            print '    EDIT: Forceusercolumn ', $self->{forceusercolumn}, ' of table ', $self->{table}, " must be type text, not $type!\n";
            $ok = 0;
        }

        if(contains($self->{forceusercolumn}, $self->{editcolumns})) {
            print '    EDIT: Forceusercolumn ', $self->{forceusercolumn}, " must not be editable!\n";
            $ok = 0;
        }
    }



    my @coltypes;
    foreach my $key (sort keys %{$self->{editcolumntypes}}) {
        push @coltypes, $key . '=' . $self->{editcolumntypes}->{$key};
    }
    $self->{editcolumnlist} = join(';', @coltypes);


    # -- Validate goto columns
    my @allcols = (@{$self->{editcolumns}}, @{$self->{readonlycolumns}});
    foreach my $gotocol (@{$self->{gotocolumns}}) {
        if($gotocol ne 'PK' && !contains($gotocol, \@allcols)) {
            print '    EDIT: Goto-Column ', $gotocol, " is not defined\n";
            $ok = 0;
        }
    }

    if($self->{useserial}) {
        $self->{serial_nextval} = '';
        my $table = $self->{table};
        my $schema = 'public';
        if($table =~ /\./) {
            ($schema, $table) = split/\./, $table;
        }
        my $nvsel = $dbh->prepare("SELECT pg_get_expr(adbin, adrelid) AS adsrc FROM pg_attrdef WHERE adrelid =
                                    (
                                        SELECT c.oid FROM pg_class c
                                        INNER JOIN pg_namespace n ON n.oid = c.relnamespace
                                        WHERE n.nspname = ?
                                        AND c.relname = ?
                                    )
                                    and pg_get_expr(adbin, adrelid) like 'nextval%';")
            or croak($dbh->errstr);
        $nvsel->execute($schema, $table) or croak($dbh->errstr);
        while((my $line = $nvsel->fetchrow_hashref)) {
            #$self->{serial_nextval} = $line->{adsrc};
            my $nvcall = $line->{adsrc};
            my @nvparts = split/\'/, $nvcall;
            if($nvparts[1] !~ /\./) {
                # No schema name given. Add schema of table
                $nvparts[1] = $schema . '.' . $nvparts[1];
            }
            $nvcall = join("'", @nvparts);
            $self->{serial_nextval} = $nvcall;
        }
        $nvsel->finish;
        $dbh->rollback;
        if($self->{serial_nextval} eq '') {
            croak("    Can't find nextval call for sequence!");
        }
    }


    finishreload:

    if(!$ok) {
        #print Dumper($self);
        croak("Can't initialize module " . $self->{modname} . " due to config errors!");
    }

    return;
}

sub validateEditItem($self, $item, $multiarraymode) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    foreach my $required (qw[type]) {
        if(!defined($item->{$required})) {
            print "    EDIT: Attribute \"$required\" not set!\n";
            return 0;
        }
    }

    if($item->{type} eq 'multiarray') {
        if($multiarraymode) {
            print "    EDIT: nested multiarrays are not supported!\n";
            return 0;
        }

        if(!defined($item->{headers})) {
            print "    EDIT: multiarray does not specify headers!\n";
            return 0;
        }

        if(!defined($item->{spares})) {
            #print "    EDIT: multiarray does not specify spares, defaulting to 5!\n";
            $item->{spares} = 5;
        }

        # Split the headers into an array
        my @headertemp = split/\|/, $item->{headers};
        $item->{header} = \@headertemp;

        if(scalar @{$item->{header}} != scalar @{$item->{item}}) {
            print "    EDIT: multiarray number of headers does not match number of columns!\n";
            return 0;
        }


        my $ok = 1;
        for(my $i = 0; $i < scalar @{$item->{item}}; $i++) {
            my $subitem = $item->{item}->[$i];

            # Enforce subtable formatting rules
            if($i+1 == scalar @{$item->{item}}) {
                # Last item ends row
                $subitem->{columnbreak} = 0;
                $subitem->{linebreak} = 1;
            } else {
                $subitem->{columnbreak} = 1;
                $subitem->{linebreak} = 0;
            }

            if(!$self->validateEditItem($subitem, 1)) {
                $ok = 0;
            }
        }

        if(!$ok) {
            return 0;
        }

        return 1;
    }

    foreach my $optional (qw[header]) {
        if(!defined($item->{$optional})) {
            #print "    EDIT: Attribute \"$optional\" not set, defaulting to empty string!\n";
            $item->{$optional} = '';
        }
    }

    if($item->{type} eq 'newtab') {
        # A "newtab" item. Just remember we want to use
        # Tabs in the template, generate a sanitized tab name,
        # then go on to the next item
        $self->{usetabs} = 1;
        my $temp = $item->{header};
        $temp =~ s/[^a-zA-Z0-9]/_/g;
        $item->{tabname} = 'tabs-' . lc $temp;
        $item->{tablename} = shift @{$self->{tabstablenames}};
        return 1;
    }

    if($item->{type} eq 'startsubtable') {
        # Subtable items are HTML laqyout items only.
        my @headertemp = split/\|/, $item->{headers};
        $item->{header} = \@headertemp;
        return 1;
    }
    if($item->{type} eq 'endsubtable') {
        # Subtable items are HTML laqyout items only.
        return 1;
    }

    foreach my $required (qw[column]) {
        if(!defined($item->{$required})) {
            print "    EDIT: Attribute \"$required\" not set!\n";
            return 0;
        }
    }

    if(!defined($item->{linebreak}) || $item->{linebreak} != 0) {
        $item->{linebreak} = 1;
    }
    if(!defined($item->{columnbreak}) || $item->{columnbreak} != 1) {
        $item->{columnbreak} = 0;
    }

    if(defined($item->{goto}) && $item->{goto} =~ /\[(.*)\]/) {
        my $tmp = $1;
        if(!contains($tmp, $self->{gotocolumns})) {
            push @{$self->{gotocolumns}}, $1;
        }
    }


    if(contains($item->{column}, $self->{readonlycolumns}) || contains($item->{column}, $self->{editcolumns})) {
        print "    EDIT: Duplicate column $item->{column}!\n";
        return 0;
    }

    if(contains($item->{type}, $self->{readonlytypes}) && $item->{column} ne $self->{primarykey}) {
        push @{$self->{readonlycolumns}}, $item->{column};
    } else {
        push @{$self->{editcolumns}}, $item->{column};
    }
    $self->{editcolumnnullable}->{$self->columnBasename($item->{column})} = 0;
    if(!defined($item->{nullable}) || !$item->{nullable} || $item->{type} eq 'enumarray') {
        $item->{nullable} = 0;
    } else {
        $item->{nullable} = 1;
        $self->{editcolumnnullable}->{$self->columnBasename($item->{column})} = 1;
    }

    if(!defined($item->{mustfield}) || !$item->{mustfield}) {
        $item->{mustfield} = 0;
    } else {
        $item->{mustfield} = 1;
    }

    if($item->{type} eq 'enumarray' || $item->{type} eq 'enum' || $item->{type} eq 'subenum') {
        if(!defined($item->{extendable})) {
            #print "    EDIT: type $item->{type} does not define 'extendable', defaulting to 0\n";
            $item->{extendable} = 0;
        }
    }

    if($item->{type} eq 'enumarray' && !defined($item->{spares})) {
        #print "    EDIT: type $item->{type} does not define 'spares', defaulting to 5\n";
        $item->{spares} = 5;
    }

    if(!contains($item->{type}, $self->{editallowedtypes})) {
            print "    EDIT: type $item->{type} not supported!\n";
            return 0;
    }

    my $colname = $item->{column};
    if($multiarraymode) {
        $colname = $self->columnAddIndex($colname, 1);
    }
    my $type = $dbh->getColumnType($self->{table}, $colname);
    if(!defined($type)) {
        print '    EDIT: Column ', $item->{column}, ' of table ', $self->{table}, " does not exist!\n";
        return 0;
    }

    my %testtypes = (
        array   => [qw[array]],
        boolean => [qw[led switch checkbox]],
        text => [qw[text textarray textarea textarea-readonly editor scripteditor codedisplay number enum subenum enumarray display hidden colorpicker image imagedisplay]],
        integer => [qw[number enum subenum enumarray display slider]],
        bigint => [qw[number enum subenum enumarray display slider]],
        real => [qw[number enum subenum enumarray display]],
        timestamp => [qw[date display]],
        date => [qw[dateonly display]],
        time => [qw[timeonly display]],
    );

    foreach my $testtype (keys %testtypes) {
        if($type eq $testtype && !contains($item->{type}, $testtypes{$testtype})) {
            print '    EDIT: Column ', $item->{column}, ' of table ', $self->{table}, " type is $testtype but configured isn't any of (",
                    join(',',@{$testtypes{$testtype}}) , ")! but $item->{type}\n";
            return 0;
        }
    }

    if($item->{type} eq "enum" || $item->{type} eq "subenum" || $item->{type} eq "enumarray") {
        if(!defined($item->{searchable})) {
            $item->{searchable} = 0;
        }
        if(!defined($item->{colorselector})) {
            $item->{colorselector} = 0;
        }
        if(!defined($item->{descriptiononly})) {
            $item->{descriptiononly} = 0;
        }
        if(!defined($item->{multilanguage})) {
            $item->{multilanguage} = 0;
        }

        if(!defined($item->{enumtable})) {
            print '    EDIT: Column ', $item->{column}, " does not define \"enumtable\"!\n";
            return 0;
        }
        if(!defined($item->{enumcolumn})) {
            print '    EDIT: Column ', $item->{column}, " does not define \"enumcolumn\"!\n";
            return 0;
        }

        my $enumtype = $dbh->getColumnType($item->{enumtable}, $item->{enumcolumn});
        if(!defined($enumtype)) {
            print '    EDIT: Column ', $item->{column}, " does reference nonexistant enumtable/enumvalue!\n";
            return 0;
        }

        if($enumtype ne $type) {
            print '    EDIT: Column ', $item->{column}, " has type mismatch with enum! ($enumtype vs $type)\n";
            return 0;
        }

        if($item->{type} eq "subenum") {
            if(!defined($item->{parentcolumn})) {
                print '    EDIT: Column ', $item->{column}, " does not define \"parentcolumn\"!\n";
                return 0;
            }

            if(!defined($item->{enumparentcolumn})) {
                print '    EDIT: Column ', $item->{column}, " does not define \"enumparentcolumn\"!\n";
                return 0;
            }

            my $subenumtype = $dbh->getColumnType($item->{enumtable}, $item->{enumparentcolumn});
            if(!defined($subenumtype)) {
                print '    EDIT: Column ', $item->{column}, " does reference nonexistant enumtable/enumparentcolumn!\n";
                return 0;
            }

            if(!contains($item->{parentcolumn}, $self->{editcolumns}) && !contains($item->{parentcolumn}, $self->{readonlycolumns})) {
                print '    EDIT: Parent column ', $item->{parentcolumn}, " for " . $item->{column} . " not defined yet\n";
                return 0;
            }
        }

        if(defined($item->{showdescription})) {
            my $descriptiontype = $dbh->getColumnType($item->{enumtable}, $item->{showdescription});
            if(!defined($descriptiontype)) {
                print '    EDIT: Column ', $item->{showdescription}, " does reference nonexistant enumtable/description!\n";
                return 0;
            }
        }
    }


    if($item->{type} eq "slider") {
        if(!defined($item->{value_min})) {
            print '    EDIT: Column ', $item->{column}, " does not define \"value_min\"!\n";
            return 0;
        }
        if(!defined($item->{value_max})) {
            print '    EDIT: Column ', $item->{column}, " does not define \"value_max\"!\n";
            return 0;
        }
        if(!defined($item->{step})) {
            print '    EDIT: Column ', $item->{column}, " does not define \"step\"!\n";
            return 0;
        }
    }

    if($item->{type} eq "number") {
        if(!defined($item->{value_min})) {
            print '    EDIT: Column ', $item->{column}, " does not define \"value_min\"!\n";
            return 0;
        }
        if(!defined($item->{value_max})) {
            print '    EDIT: Column ', $item->{column}, " does not define \"value_max\"!\n";
            return 0;
        }
        if(!defined($item->{hasdecimal})) {
            print '    EDIT: Column ', $item->{column}, " does not define \"hasdecimal\"!\n";
            return 0;
        } else {
            $item->{step} = 1 / (10 ** $item->{hasdecimal});
        }
    }

    if($item->{type} eq "checkbox") {
        if(!defined($item->{callback})) {
            #print '    EDIT: Checkbox column ', $item->{column}, " does not define \"callback\", disabling callback functionality!\n";
            $item->{callback} = '';
        }
        if(!defined($item->{realvalue})) {
            #print '    EDIT: Checkbox column ', $item->{column}, " does not define \"realvalue\", setting to '1'!\n";
            $item->{realvalue} = '1';
        }
        if(!defined($item->{realinactivevalue})) {
            #print '    EDIT: Checkbox column ', $item->{column}, " does not define \"realinactivevalue\", setting to '0'!\n";
            $item->{realinactivevalue} = '0';
        }
        if(!defined($item->{delete})) {
            #print '    EDIT: Checkbox column ', $item->{column}, " does not define \"delete\", setting to '0'!\n";
            $item->{delete} = '0';
        }
    }

    if($item->{type} eq "editor") {
        $self->{needcvceditor} = 1;
    }

    if($item->{type} eq "scripteditor") {
        $self->{needscripteditor} = 1;
    }
    
    # make sure we set a default size for text (if not set in config),
    if($item->{type} eq 'text') {
        if(!defined($item->{size})) {
            #print '    EDIT: Column ', $item->{column}, " has no 'size' setting, defaulting to 60\n";
            $item->{size} = 60;
        }
        if(!defined($item->{maxlength})) {
            #print '    EDIT: Column ', $item->{column}, " has no 'maxlength' setting, defaulting to 200\n";
            $item->{maxlength} = 200;
        }
    }

    # make sure we set a default size for textarea types (if not set in config),
    # but disallow "rows" and "columns" on other types
    if($item->{type} =~ /^textarea/) {
        if(!defined($item->{rows})) {
            #print '    EDIT: Column ', $item->{column}, " has no 'rows' setting, defaulting to 10\n";
            $item->{rows} = 10;
        }
        if(!defined($item->{cols})) {
            #print '    EDIT: Column ', $item->{column}, " has no 'cols' setting, defaulting to 30\n";
            $item->{cols} = 30;
        }
        if(!defined($item->{charcount})) {
            #print '    EDIT: Column ', $item->{column}, " has no 'charcount' setting, disabling limit\n";
            $item->{charcount} = 0;
        }
    }

    $self->{editcolumntypes}->{$self->columnBasename($item->{column})} = $item->{type};
}

# This is a quite complex tool. Until i have found a better way, disable the ExcessComplexity warning
# of Perl::Critic
sub get($self, $ua) {

    my $mode = $ua->{postparams}->{'mode'} || 'list';
    my $primarykey = '';
    if(defined($ua->{postparams}->{'primary_key'})) {
        $primarykey = stripString($ua->{postparams}->{'primary_key'});
    }

    # Check if we can and are requested to deliver the pagescript.js
    if($ua->{url} =~ /\/pageeditscript\.js/) {
        if(!$self->{useextraeditscript}) {
            return (status => 404);
        } else {
            return $self->get_pagescript($ua, 'edit');
        }
    }

    if($ua->{url} =~ /\/pagelistscript\.js/) {
        if(!$self->{useextralistscript}) {
            return (status => 404);
        } else {
            return $self->get_pagescript($ua, 'list');
        }
    }

    if($ua->{url} =~ /\/sendcsvlist/) {
        if(!$self->{send_csv}) {
            return (status => 404);
        } else {
            return $self->send_csv($ua);
        }
    }

    if($ua->{url} =~ /\/downloadcsvlist/) {
        if(!$self->{send_csv}) {
            return (status => 404);
        } else {
            return $self->download_csv($ua);
        }
    }

    if($ua->{url} =~ /\/autosave/) {
        if(!$self->{autosave}) {
            return (status => 404);
        } else {
            return $self->get_autosave($ua);
        }
    }

    # Check if we are called to edit a specific element by external mask through url
    my $filename = $ua->{url};

    # FIXME
    my $ajaxprefix = $self->{webpath} . 'ajax';
    if($filename =~ /^$ajaxprefix/) {
        return $self->get_lines($ua);
    }

    my $remove = $self->{webpath};
    $filename =~ s/^$remove//;
    $filename =~ s/^\///;
    $filename =~ s/\/$//;
    $filename = stripString($filename);
    print STDERR "##### FILENAME $filename ######";
    if($filename ne '') {
        if($filename =~ /^NEW/) {
            $filename =~ s/^NEW\///;
            my @parts = split/#/, $filename;
            my %forceFields;
            foreach my $part (@parts) {
                my ($key, $val) = split/=/, $part;
                $forceFields{$key} = $val;
            }

            return $self->get_edit($ua, '__NEW__', \%forceFields);
        } else {
            if($self->{listonly}) {
                return $self->get_list($ua);
            }
            return $self->get_edit($ua, $filename);
        }
    }

    if($mode eq 'list' || $primarykey eq '') {
        return $self->get_list($ua);
    }

    return $self->get_edit($ua);
}

sub send_csv($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $mailh = $self->{server}->{modules}->{$self->{sendmail}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
    );

    my $csvdata = '';
    my @headers;
    my @columns;
    foreach my $item (@{$self->{list}->{item}}) {
        push @headers, $item->{header};
        push @columns, $item->{column};
    }
    $csvdata .= join(';', @headers) . "\r\n";

    my $selsth = $dbh->prepare_cached("SELECT " . join(',', @columns) . " FROM " . $self->{table})
            or croak($dbh->errstr);
    if(!$selsth->execute()) {
        $dbh->rollback;
        return(status => 500);
    }
    while((my $line = $selsth->fetchrow_hashref)) {
        my @data;
        foreach my $col (@columns) {
            push @data, $line->{$col};
        }
        $csvdata .= join(';', @data) . "\r\n";
    }
    $selsth->finish;
    $dbh->commit;

    my @recievers = ($webdata{userData}->{email_addr});
    my $mailtitle = "ListAndEdit CSV report (" . $self->{modname} . ")";
    my $mailbody = "Requested CSV report from ListAndEdit Mask";

    my $tmpfname = "/tmp/listandeditreport_" . $webdata{userData}->{user} . '_' . $self->{modname} . '.csv';
    my $zipfname = "/tmp/listandeditreport_" . $webdata{userData}->{user} . '_' . $self->{modname} . '.csv.zip';

    writeBinFile($tmpfname, $csvdata);

    $mailh->sendFiles(\@recievers, $mailtitle, $mailbody, $zipfname, $tmpfname);

    unlink $tmpfname;
    unlink $zipfname;

    return (
        status          =>  204 # "no content
    );

}

sub download_csv($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $mailh = $self->{server}->{modules}->{$self->{sendmail}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
    );

    my $csvdata = '';
    my @headers;
    my @columns;
    foreach my $item (@{$self->{list}->{item}}) {
        push @headers, $item->{header};
        push @columns, $item->{column};
    }
    $csvdata .= join(';', @headers) . "\r\n";

    my $selsth = $dbh->prepare_cached("SELECT " . join(',', @columns) . " FROM " . $self->{table})
            or croak($dbh->errstr);
    if(!$selsth->execute()) {
        $dbh->rollback;
        return(status => 500);
    }
    while((my $line = $selsth->fetchrow_hashref)) {
        my @data;
        foreach my $col (@columns) {
            push @data, $line->{$col};
        }
        $csvdata .= join(';', @data) . "\r\n";
    }
    $selsth->finish;
    $dbh->commit;

    my $filename = "listandeditreport_" . $webdata{userData}->{user} . '_' . $self->{modname} . '.csv';

    return (status  =>  200,
        type    => "text/csv",
        "Content-Disposition" => "attachment; filename=\"$filename\";",
        "Cache-Control" => 'no-cache, no-store',
        data    => $csvdata);
}


sub get_pagescript($self, $ua, $mode) {

    my $lastetag = $ua->{headers}->{'If-None-Match'} || '';
    
    my $prefix = 'extra' . $mode . 'script';

    if($self->{$prefix . '_etag'} eq $lastetag) {
        # Resource matches the cached one in the browser, so just notify
        # we didn't modify it
        return(status   => 304);
    }

    my $lastmodified = $ua->{headers}->{'If-Modified-Since'} || '';

    my %retpage = (
        status          =>  200,
        type            => "application/javascript",
        etag            => $self->{$prefix . '_etag'},
        expires         => "+1d",
        cache_control   =>  "max-age=84100",
        "Last-Modified" => $self->{$prefix . '_webdate'},
    );

    if($lastmodified ne "") {
        # Compare the dates
        my $lmclient = parseWebdate($lastmodified);
        my $lmserver = parseWebdate($self->{$prefix . '_webdate'});
        if($lmclient >= $lmserver) {
            $retpage{status} = 304;
            return %retpage;
        }
    }

    my $supportedcompress = $ua->{headers}->{'Accept-Encoding'} || '';
    if($supportedcompress =~ /gzip/io && defined($self->{$prefix . '_gzip'})) {
        $retpage{data} = $self->{$prefix . '_gzip'};
        $retpage{"Content-Encoding"} = "gzip";
        $self->extend_header(\%retpage, "Vary", "Accept-Encoding");
    } else {
        $retpage{data} = $self->{$prefix};
        $retpage{disable_compression} = 1;
    }

    return %retpage;
}

sub get_list($self, $ua, $usemasterlayout = true) {
    if($self->{editonly}) {
        return (status => 403); # Forbidden
    }
    
    my $listlength = 500;
    if(!$usemasterlayout) {
        $listlength = 300;
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sesh = $self->{server}->{modules}->{$self->{session}};

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
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $webpath,
        ajaxwebpath         =>  $self->{webpath} . 'ajax',
        candelete       =>  $self->{candelete},
        cancreate       =>  $self->{cancreate},
        UseURLID        => $self->{use_urlid},
        URLID           => $urlid,
        ListOnly        => $self->{listonly},
        ListOnlyCustomSelect => $self->{listonly_customselect},
        UseRawHTML      => 0,
        ShowPageTitle   => $self->{showpagetitle},
        ColumnFilters   => $self->{column_filters},
        AllowSendCSV        => $self->{send_csv},
        SendCSVAjaxPath     => '',
        AllowDownloadCSV        => $self->{download_csv},
        DownloadCSVAjaxPath     => '',
        ListPageHeader => $self->{listpageheader},
        ListLength     => $listlength,
        showads => $self->{list}->{showads},
        SidebarHTML => $self->{list}->{sidebarhtml},
        QuickSelect => $self->{quickselect},
    );

    if($self->{send_csv}) {
        $webdata{SendCSVAjaxPath} = $self->{webpath} . '/sendcsvlist';
    }

    if($self->{download_csv}) {
        $webdata{DownloadCSVAjaxPath} = $self->{webpath} . '/downloadcsvlist';
    }

    if($self->{support_mobile}) {
        $webdata{MobileDesktopClientMode} = 'desktop';
    }

    if($self->{userawhtml}) {
        $webdata{UseRawHTML} = 1;
    }

    my @columns;
    my $colcount = 0;
    foreach my $item (@{$self->{list}->{item}}) {
        my %column = (
            header  => $item->{header},
            colname => $item->{column},
        );
        push @columns, \%column;
        $colcount++;
    }
    $webdata{columns} = \@columns;
    $webdata{column_count} = $colcount;
    $webdata{iGuessStats} = $self->{guess_stats};

    my $lastfilter = $sesh->get($self->{sessionname} . '::lastFilter') || "";
    $lastfilter = dbderef($lastfilter);
    $lastfilter =~ s/\"/\'/g;
    $webdata{sSearch} = $lastfilter;

    my $lastsort = $sesh->get($self->{sessionname} . '::lastSort') || "";
    $lastsort = dbderef($lastsort);

    if($lastsort eq '') {
        # Make sorting the default sort order
        $lastsort = $self->{defaultlastsort};
    }

    $webdata{aaSorting} = $lastsort;
    
    if($self->{column_filters}) {
        my $rawfilters = $sesh->get($self->{sessionname} . '::rawColumnFilters') || "";
        $rawfilters = dbderef($rawfilters);
    
        if($rawfilters eq '') {
            # Make sorting the default sort order
            $rawfilters = [];
        }
    
        $webdata{rawColumnFilters} = $rawfilters;
    }
    
    #$sesh->set($self->{sessionname} . '::rawColumnFilters', $rawjson);
    
    my @headextrascripts;
    
    if($self->{useextralistscript}) {
        push @headextrascripts, $self->{webpath} . '/pagelistscript.js';
    }
    
    $webdata{HeadExtraScripts} = \@headextrascripts;

    if($self->{mastertemplate} ne '') {
        $usemasterlayout = $self->{mastertemplate};
    }

    my $template = $self->{server}->{modules}->{templates}->get("listandedit/list", $usemasterlayout, %webdata);
    return (status  =>  404) unless $template;
    if($self->{support_mobile}) {
        return (status  =>  200,
            type    => "text/html",
            data    => $template,
            'Vary'    => 'User-Agent', # <-- Signal google we support mobile on this page
        );
    }
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_lines($self, $ua) {


    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sesh = $self->{server}->{modules}->{$self->{session}};
    my $method = $ua->{method};


    my $limit = $ua->{postparams}->{'length'} || 10;
    my $offset = $ua->{postparams}->{'start'} || 0;
    my $draworder = $ua->{postparams}->{'draw'} || 0;
    if($draworder eq 'NaN') {
        print STDERR "Draworder is NaN! You did something wrong in past replies, most likely sending a string instead of a number!\n";
    }

    my $webpath = $ua->{url};
    my $urlid = '';
    if($self->{use_urlid}) {
        $urlid = $webpath;
        $urlid =~ s/^.*\///;
        $urlid = decode_uri_path($urlid);
    }

    my @pkparts;
    foreach my $pkitem (@{$self->{primarykey}->{item}}) {
        push @pkparts, $pkitem->{column};
    }
    my $primkey = join(" || '\$\$PKJ\$\$' || ", @pkparts);

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
    );

    my $userlang = $webdata{UserLanguage} || "eng";
    my %translations = (
        bool_true => tr_translate($userlang, "True"),
        bool_false => tr_translate($userlang, "False"),
    );

    my %params = %{$ua->{postparams}};
    my $where = '';

    if(defined($self->{restrict}) && $self->{restrict} ne '') {
        foreach my $clauseitem (@{$self->{restrict}->{item}}) {
            my $vtmp = $clauseitem->{value};
            if($vtmp =~ /USER/) {
                $vtmp =~ s/USER/$webdata{userData}->{user}/g;
            }
            if($self->{use_urlid} && $vtmp =~ /URLID/) {
                $vtmp =~ s/URLID/$urlid/g;
            }
            if($where ne '') {
                $where .= ' AND ';
            }
            my $comparator = '=';
            if(defined($clauseitem->{negate}) && $clauseitem->{negate}) {
                $comparator = '!=';
            }
            $where .= $clauseitem->{column} . ' ' . $comparator . ' ' . $dbh->quote($vtmp) . ' ';
        }
    }

    my $search = $ua->{postparams}->{'search[value]'} || '';
    $sesh->set($self->{sessionname} . '::lastFilter', $search);
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

            if(!defined($self->{filtercolumn})) {
                if(!$negate) {
                    foreach my $col (@{$self->{wherecolumns}}) {
                        my $subclause = $col . "::text ILIKE $sp";
                        push @subclauses, $subclause;
                    }
                    $where .= ' ( ' . join(' OR ', @subclauses) . ' ) ';
                } else {
                    foreach my $col (@{$self->{wherecolumns}}) {
                        my $subclause = $col . "::text NOT ILIKE $sp";
                        push @subclauses, $subclause;
                    }
                    $where .= ' ' . join(' AND ', @subclauses) . ' ';
                }
            } else {
                # use (hopefully) optimized filter column
                $where .= ' ' . $self->{filtercolumn} . ' ';
                if($negate) {
                    $where .= 'NOT ';
                }
                $where .= "LIKE $sp";
            }
        }

    }

    if($self->{column_filters}) {
        my $colnum = -1;
        if(!$self->{listonly} || $self->{listonly_customselect}) {
            $colnum++;
        }
        my $colwhere = '';
        my @rawfilters;
        foreach my $col (@{$self->{wherecolumns}}) {
            $colnum++;

            my $colfilter = $ua->{postparams}->{'columns[' . $colnum . '][search][value]'} || '';
            if($colfilter ne '') {
                my %rawfilter = (
                    column => $col,
                    filter => $colfilter,
                );
                push @rawfilters, \%rawfilter;
            }

            my $not = '';
            $colfilter = stripString($colfilter);
            next if($colfilter eq '');
            if(substr($colfilter, 0, 1) eq '!') {
                $not = 'NOT';
                substr($colfilter, 0, 1, '');
            }
            next if($colfilter eq '');


            $colfilter = $dbh->quote($colfilter);
            # Insert the percent signs
            $colfilter =~ s/^\'/\'%/;
            $colfilter =~ s/\'$/%\'/;
            my $subclause = $col . "::text $not ILIKE $colfilter";
            if($colwhere ne '') {
                $colwhere .= ' AND ';
            }
            $colwhere .= " $subclause ";
        }
        if($colwhere ne '') {
            if($where ne '') {
                $where .= ' AND ';
            }
            $where .= " $colwhere ";
        }

        $sesh->set($self->{sessionname} . '::rawColumnFilters', \@rawfilters);
    }
    
    $sesh->set($self->{sessionname} . '::lastWhere', $where);

    if($where ne '') {
        $where = "WHERE $where ";
    }

    my $orderby = $self->{orderby};
    my @orderjs;
    if(defined($ua->{postparams}->{'order[0][dir]'})) {
        my $sortcount = 0;
        while(1) {
            last if(!defined($ua->{postparams}->{'order[' . ($sortcount + 1) . '][dir]'}));
            $sortcount++;
        }
        my @sortcols;
        my $sortoffs = 0;
        if(!$self->{listonly} || $self->{listonly_customselect}) {
            $sortoffs = 1;
        }
        for(my $i = 0; $i <= $sortcount; $i++) {
            my $sortnum = $ua->{postparams}->{'order[' . $i . '][column]'} || 0;

            if(!$self->{listonly} || $self->{listonly_customselect}) {
                if($sortnum == 0) {
                    # Selector column, ignore
                    next;
                }

            }
            my $sort = $self->{listcolumnsnameonly}->[$sortnum - $sortoffs]; # Selector column does not really exist, move calc one over to the left
            my $dir = $ua->{postparams}->{'order[' . $i . '][dir]'} || 'asc';
            if($dir !~ /asc/i) {
                $sort .= ' DESC';
                push @orderjs, [$sortnum, "desc"];
                #push @orderjs, '[' . $sortnum . ',\'desc\']' ;
            } else {
                push @orderjs, [$sortnum, "asc"];
                #push @orderjs, '[' . $sortnum . ',\'asc\']' ;
            }
            push @sortcols, $sort;
        }

        if(@sortcols) {
            $orderby = join(', ', @sortcols);
        }
    }

    my $orderjson = encode_json \@orderjs;
    $sesh->set($self->{sessionname} . '::lastSort', $orderjson);
    $sesh->set($self->{sessionname} . '::lastOrderBy', $orderby);


    my $tcountsth;
    if($self->{guess_stats}) {
        # Aproximate total number of lines in the table by accessing the statistics (much faster than actual counting)
        #$tcountsth = $dbh->prepare_cached("SELECT reltuples::integer FROM pg_class WHERE relname = '" . $self->{table} . "'")
        #        or croak($dbh->errstr);
        $tcountsth = $dbh->prepare_cached("SELECT row_count FROM table_statistics WHERE tablename = '" . $self->{table} . "'")
                or croak($dbh->errstr);
    } else {
        $tcountsth = $dbh->prepare_cached("SELECT count(*) FROM " . $self->{table})
                or croak($dbh->errstr);
    }
    $tcountsth->execute or croak($dbh->errstr);
    my ($tcount) = $tcountsth->fetchrow_array;
    $tcountsth->finish;
    if(!defined($tcount)) {
        $tcount = 0;
    }

    {
        my @columns;
        my $colcount = 0;
        foreach my $item (@{$self->{list}->{item}}) {
            my %column = (
                header  => $item->{header},
            );
            push @columns, \%column;
            $colcount++;
        }
        $webdata{columns} = \@columns;
        $webdata{column_count} = $colcount;
    }

    my $downloadstmt = "SELECT " . join(', ', @{$self->{listcolumns}}) .
                    " FROM " . $self->{table} .
                    " $where " .
                    " ORDER BY $orderby";

    $sesh->set($self->{sessionname} . '::lastSelect', $downloadstmt);

    my $selstmt = "SELECT $primkey AS primarykey, " . join(', ', @{$self->{listcolumns}}) .
                    ", count(*) OVER () as whereclause_totalcount " .
                    " FROM " . $self->{table} .
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

        if(!$self->{listonly} || $self->{listonly_customselect}) {
            my $primval = $rawline->{primarykey};
            $primval = encode_entities($primval, "'<>&\"\n");
            $primval =~ s/ä/&auml;/g;
            $primval =~ s/ö/&ouml;/g;
            $primval =~ s/ü/&uuml;/g;
            $primval =~ s/Ä/&Auml;/g;
            $primval =~ s/Ö/&Ouml;/g;
            $primval =~ s/Ü/&Uuml;/g;
            $primval =~ s/ß/&szlig;/;
            my $primfield;
            if(!$self->{quickselect}) {
                $primfield = '<input type="radio" name="primary_key" value="' . $primval . '" ' . $self->{radiobuttonhtml} . '>';
            } else {
                $primfield = '<input type="button" value=" 🖉 " onclick="quickSelect(\'' . $primval . '\');">';
            }

            push @columns, $primfield;
        }

        foreach my $item (@{$self->{list}->{item}}) {
            my $type    =  $item->{type};
            if(!defined($rawline->{$item->{column}})) {
                $rawline->{$item->{column}} = '';
            }
            my $value   =  "" . $rawline->{$item->{column}};

            if($type eq 'date') {
                $type = 'text';
                $value =~ s/\..*//;
            } elsif($type eq 'array' || $type eq 'textarray') {
                if(ref $rawline->{$item->{column}} eq 'ARRAY') {
                    $value = join("<br/>", @{$rawline->{$item->{column}}});
                } else {
                    $value = '';
                }
            } elsif($type eq 'boolean') {
                if(defined($item->{booleantruevalue})) {
                    if($value eq $item->{booleantruevalue}) {
                        $value = '<div class="TRUEBOOLEAN">' . $value . '</div>';
                    } else {
                        $value = '<div class="FALSEBOOLEAN">' . $value . '</div>';
                    }
                } else {
                    if($value) {
                        $value = '<div class="TRUEBOOLEAN">' . $translations{bool_true} . '</div>';
                    } else {
                        $value = '<div class="FALSEBOOLEAN">' . $translations{bool_false} . '</div>';
                    }
                }
            } elsif($type eq 'led') {
                if($value) {
                    $value = '<img src="/pics/led_OK.png" alt="ON">';
                } else {
                    $value = '<img src="/pics/led_ERROR.png" alt="OFF">';
                }
            } elsif($type eq 'html') {
                # Assume it's all properly preformatted
            } elsif($type eq 'url') {
                my $temp = $item->{urlformat};
                my $encodedvalue = encode_uri_path($value, $item->{encodeslashes});
                $temp =~ s/\%/$encodedvalue/;
                $value = '<a href="' . $temp . '">' . $value . '</a>';
            } elsif($type eq 'color') {
                my $contrast = colorHexMaxContrast($value);
                $value = '<div style="background-color:' . $value . ';color:' . $contrast . ';">' . $value . '</div>';
            } elsif($type eq 'colorswatch') {
                $value = colorSwatchHTML($value);
            } elsif($type eq 'image') {
                if($value ne '') {
                    $value = '<img src="data:image/png;base64,' . $value . '">';
                }
            } else {
                $value = encode_entities($value, "'<>&\"");
                $value =~ s/ä/&auml;/g;
                $value =~ s/ö/&ouml;/g;
                $value =~ s/ü/&uuml;/g;
                $value =~ s/Ä/&Auml;/g;
                $value =~ s/Ö/&Ouml;/g;
                $value =~ s/Ü/&Uuml;/g;
                $value =~ s/ß/&szlig;/g;
                $value =~ s/\R/<br>/g;
            }


            # Limit size of content if length is defined
            if($item->{type} eq 'text' && $item->{length} > 0 && length($value) > $item->{length}) {
                my $newlen = length($value) - 3;
                if($newlen > 0) {
                    $value = substr $value, 0, $newlen;
                    $value .= '...';
                }
            }

            push @columns, $value;
        }

        push @lines, \@columns;
    }
    $selsth->finish;
    $dbh->rollback;
    $webdata{aaData} = \@lines;

    if($tcount < $fcount) {
        $tcount = $fcount;
    }
    $webdata{recordsTotal} = $tcount;
    $webdata{recordsFiltered} = $fcount;
    $webdata{draw} = 0 + $draworder;

    my $jsondata = encode_json \%webdata;

    return (status  =>  200,
            type    => "application/json",
            data    => $jsondata,
            "__do_not_log_to_accesslog" => 1,
        );
}

sub get_prevnext($self, $ua, $currentprimkey) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sesh = $self->{server}->{modules}->{$self->{session}};

    my $webpath = $ua->{url};
    my $urlid = '';
    if($self->{use_urlid}) {
        $urlid = $webpath;
        $urlid =~ s/^.*\///;
        $urlid = decode_uri_path($urlid);
    }

    my @pkparts;
    foreach my $pkitem (@{$self->{primarykey}->{item}}) {
        push @pkparts, $pkitem->{column};
    }
    my $primkey = join(" || '\$\$PKJ\$\$' || ", @pkparts);
    my $where = $sesh->get($self->{sessionname} . '::lastWhere') || "";
    if($where ne '') {
        $where = "WHERE $where";
    }
    
    my $orderby = $sesh->get($self->{sessionname} . '::lastOrderBy') || "";
    if($orderby ne '') {
        $orderby = "ORDER BY $orderby";
    }
    
    my $selsth = $dbh->prepare_cached("SELECT $primkey AS primarykey 
                                        FROM $self->{table}
                                        $where
                                        $orderby")
            or croak($dbh->errstr);
    
    if(!$selsth->execute()) {
        $dbh->rollback;
        return ('', '');
    }
    my $prev = '';
    my $cur = '';
    my $next = '';
    my $found = 0;
    while((my $line = $selsth->fetchrow_hashref)) {
        $prev = $cur;
        $cur = $line->{primarykey};
        if($cur eq $currentprimkey) {
            $found = 1;
            if((my $nextline = $selsth->fetchrow_hashref)) {
                $next = $nextline->{primarykey}
            }
            last;
        }
    }
    
    $selsth->finish;
    $dbh->commit;
    
    if($found) {
        return ($prev, $next);
    }
    
    return ('', '');
}

sub get_edit($self, $ua, $forcePrimaryKey = undef, $forceFields = undef) {

    if($self->{listonly}) {
        return (status => 403); # Forbidden
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $mode = $ua->{postparams}->{'mode'} || 'list';

    # re-bracketify encoded postparam names
    if(defined($ua->{postparams}) && ref $ua->{postparams} eq 'HASH') {
        foreach my $key (keys %{$ua->{postparams}}) {
            my $newkey = '' . $key;
            $newkey =~ s/XXXLEFTBRACKETXXX/\[/g;
            $newkey =~ s/XXXRIGHTBRACKETXXX/\]/g;
            if($key ne $newkey) {
                #print STDERR "Changing $key to $newkey\n";
                $ua->{postparams}->{$newkey} = $ua->{postparams}->{$key};
                delete $ua->{postparams}->{$key};
            }
        }
        #print STDERR p(%{$ua->{postparams}});
    }


    my $primarykey = '';
    if(defined($ua->{postparams}->{'primary_key'})) {
        #$primarykey = stripString($ua->{postparams}->{'primary_key'});
        $primarykey = $ua->{postparams}->{'primary_key'};
    }

    if($mode =~ /^select\_(.*)/) {
        $primarykey = $1;
        $mode = 'select';
    }
    
    if($mode eq 'copy') {
        if(!$self->{cancopy}) {
            return (status => 403); # Forbidden!
        }
        $primarykey = '__NEW__';
        $mode = 'create';
    }
    
    my $saveandclose = 0;
    if($mode eq 'editandclose') {
        $mode = 'edit';
        $saveandclose = 1;
    }

    my $selectedTab = $ua->{postparams}->{'selectedTab'} || '';

    if(defined($forcePrimaryKey) && $forcePrimaryKey ne '') {
        $mode = 'select';
        $primarykey = $forcePrimaryKey;
    }

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        candelete       =>  $self->{candelete},
        cancreate       =>  $self->{cancreate},
        cancopy         =>  $self->{cancopy},
        cansaveandclose =>  $self->{cansaveandclose},
        autosave        =>  $self->{autosave},
        editcolumnlist  =>  $self->{editcolumnlist},
        extrattvars     =>  $self->{extrattvars},
        EditPageHeader => $self->{editpageheader},
        showads => $self->{edit}->{showads},
        SidebarHTML => $self->{edit}->{sidebarhtml},
    );

    if($self->{autosave}) {
        $webdata{PAGECAMELPAGEFOOTERCOLOR} = 'white';
        $webdata{PAGECAMELPAGEFOOTERTEXT} = 'Initializing Autosave';
    }


    my @pkparts = split/\$\$PKJ\$\$/, $primarykey;
    my $errstr = '';
    my $okstr = '';
    my $isSelect = 0;

    my @pkcols;
    foreach my $pkitem (@{$self->{primarykey}->{item}}) {
        push @pkcols, $pkitem->{column};
    }

    if(defined($self->{restrict})) {
        # Force "restrict" columns in primary key
        for(my $i = 0; $i < scalar @pkcols; $i++) {
            foreach my $clauseitem (@{$self->{restrict}->{item}}) {
                next if($clauseitem->{column} ne $pkcols[$i]);
                $pkparts[$i] = $clauseitem->{value};
                if($pkparts[$i] =~ /USER/) {
                    $pkparts[$i] =~ s/USER/$webdata{userData}->{user}/g;
                }
            }
        }

        # Make sure that forceFields from URL don't override restricted columns
        if(defined($forceFields)) {
            foreach my $clauseitem (@{$self->{restrict}->{item}}) {
                $forceFields->{$clauseitem->{column}} = $clauseitem->{value};
                if($forceFields->{$clauseitem->{column}} =~ /USER/) {
                    $forceFields->{$clauseitem->{column}} =~ s/USER/$webdata{userData}->{user}/g;
                }
            }
        }
    }

    my %testtypes = (
        array   => [qw[array]],
        boolean => [qw[led switch checkbox]],
    );

    my $newprimkey;
    if($mode eq 'delete') {
        return (status  =>  403) unless $self->{candelete};
        my $delsth = $dbh->prepare_cached("DELETE FROM " . $self->{table} .
                                          " WHERE " . join(' = ? AND ', @pkcols) . " = ? ")
                or croak($dbh->errstr);
        if(!$delsth->execute(@pkparts)) {
            $errstr = $dbh->errstr;
            $dbh->rollback;
            $mode = 'edit';
        } else {
            $dbh->commit;
            if($self->{generateauditlog}) {
                $self->write_auditlog($webdata{userData}->{user}, 'delete', @pkparts);
            }
            return $self->get_list($ua);
        }
    } elsif($mode eq 'edit') {
        my @collist;
        foreach my $cname (@{$self->{editcolumns}}) {
            push @collist, $self->columnBasename($cname);
        }
        if(defined($self->{forceusercolumn})) {
            push @collist, $self->{forceusercolumn};
        }

        my $upstmt = "UPDATE "  . $self->{table} . " SET " .
                        join(' = ?, ', @collist) . " = ? " .
                        "WHERE " . join(' = ? AND ', @pkcols) . " = ? ";
        my $upsth = $dbh->prepare_cached($upstmt) or croak($dbh->errstr);
        my @upargs;
        my $fieldsok = 1;
        foreach my $cname (@{$self->{editcolumns}}) {
            my $column = $self->columnBasename($cname);
            my $multiarraymode = 0;
            if($column ne $cname) {
                $multiarraymode = 1;
            }

            my $arraycount = '';
            if(defined($ua->{postparams}->{$column . '_count'})) {
                $arraycount = stripString($ua->{postparams}->{$column . '_count'});
            }
            if($arraycount eq '') {
                my $tmp = '';
                if(defined($ua->{postparams}->{$column})) {
                    $tmp = stripString($ua->{postparams}->{$column});
                }

                # Force "restrict" columns
                if(defined($self->{restrict})) {
                    foreach my $clauseitem (@{$self->{restrict}->{item}}) {
                        next if($clauseitem->{column} ne $column);
                        $tmp = $clauseitem->{value};
                        if($tmp =~ /USER/) {
                            $tmp =~ s/USER/$webdata{userData}->{user}/g;
                        }
                    }
                }

                if(contains($self->{editcolumntypes}->{$column}, $testtypes{boolean})) {
                    if($tmp eq '1' || $tmp =~ /^on$/i) {
                        $tmp = 1;
                    } else {
                        $tmp = 0;
                    }
                } elsif ($self->{editcolumntypes}->{$column} eq 'date' || $self->{editcolumntypes}->{$column} eq 'dateonly') {
                    if($tmp eq '-- ::' || $tmp !~ /\d+/) {
                        # Compensate for datetimepicker empty template or when field is empty
                        $tmp = 'now';
                    }
                    if($tmp eq '') {
                        $tmp = 'now';
                    }

                    # Check if this column defines a default value
                    if($tmp eq 'now') {
                        foreach my $item (@{$self->{edit}->{item}}) {
                            if(defined($item->{column}) && $item->{column} eq $column) {
                                if(defined($item->{default}) && $item->{default} ne '') {
                                    $tmp = $item->{default};
                                }
                                last;
                            }
                        }
                    }

                    $tmp = parseNaturalDate($tmp);
                    if( $self->{editcolumntypes}->{$column} eq 'dateonly') {
                        $tmp =~ s/\ .*//;
                    }
                } elsif ($self->{editcolumntypes}->{$column} eq 'number' || $self->{editcolumntypes}->{$column} eq 'slider') {
                    # make sure we always use the dot as a comma
                    $tmp =~ s/\,/./g;
                    if($tmp eq '') {
                        $tmp = 0;
                    } else {
                        $tmp = 0 + $tmp;
                    }
                    
                } elsif($self->{editcolumntypes}->{$column} eq 'textarea') {
                    # Re-read unstripped value so we don't remove required line breaks
                    $tmp = $ua->{postparams}->{$column} || '';
                    $tmp =~ s/\r//g;
                    $tmp =~ s/\n{3,}/\n\n/g;
                    $tmp =~ s/\n+$//g;
                } elsif($self->{editcolumntypes}->{$column} eq 'scripteditor') {
                    $tmp = $ua->{postparams}->{$column} || '';
                    $tmp =~ s/\r//g;
                    # Don't remove extra newlines
                    $tmp =~ s/\n+$//g;
                } elsif($self->{editcolumntypes}->{$column} eq 'editor') {
                    $tmp = $ua->{postparams}->{$column} || '';
                    $tmp =~ s/\n+$//g;
                } elsif($self->{editcolumntypes}->{$column} eq 'image') {
                    $tmp = $ua->{postparams}->{$column} || '';
                    my $newfname = $ua->{postparams}->{$column . '___new'} || '';
                    if($newfname ne '' && defined($ua->{files}->{$newfname})) {
                        $tmp = encode_base64($ua->{files}->{$newfname}->{data});
                    }
                    my $tmpremove = $ua->{postparams}->{$column . '__remove'} || '';
                    if($tmpremove eq "1") {
                        $tmp = '';
                    }
                }

                if($self->{editcolumnnullable}->{$column} && $tmp eq '') {
                    $tmp = undef;
                }
                
                # Make sure we don't have empty PK fields. Ignore useserial on editing, we can NEVER have an empty PK column during EDIT!
                if(contains($column, \@pkcols)) {
                    if(!defined($tmp) || $tmp eq '') {
                        $fieldsok = 0;
                        $errstr .= "Field $column can not be empty (PRIMARY KEY)! ";
                    }
                }

                push @upargs, $tmp;
            } else {
                my @uparray;
                for(my $i = 0; $i < $arraycount; $i++) {
                    my $tmp = '';
                    if(defined($ua->{postparams}->{$column . '_' . $i })) {
                        if($self->{editcolumntypes}->{$column} eq 'enumarray' || $self->{editcolumntypes}->{$column} eq 'enum') {
                            # Don't stripString when dealing with enums
                            $tmp = $ua->{postparams}->{$column . '_' . $i };
                        } else {
                            $tmp = stripString($ua->{postparams}->{$column . '_' . $i });
                        }
                    }
                    if($tmp eq '') {
                        if($multiarraymode || $self->{editcolumnnullable}->{$column}) {
                            $tmp = undef;
                        } else {
                            if($self->{editcolumntypes}->{$column} eq 'number' || $self->{editcolumntypes}->{$column} eq 'checkbox') {
                                $tmp = 0;
                            }
                        }
                    }
                    if($multiarraymode || $tmp ne '') {
                        push @uparray, $tmp;
                    }
                }
                push @upargs, \@uparray;
            }
        }
        if(defined($self->{forceusercolumn})) {
            push @upargs, $webdata{userData}->{user};
        }
        if($fieldsok) {
            if($upsth->execute(@upargs,@pkparts)) {
                $dbh->commit;
                $okstr = "Updated";
            } else {
                $errstr = $dbh->errstr;
                $dbh->rollback;
            }
        }
        if($self->{generateauditlog}) {
            $self->write_auditlog($webdata{userData}->{user}, 'edit', @upargs, @pkparts);
        }
    } elsif($mode eq 'create') {
        return (status  =>  403) unless $self->{cancreate};

        my $fieldsok = 1;
        my @createcolumns = @{$self->{editcolumns}};
        foreach my $pkitem (@pkcols) {
            if(!contains($pkitem, \@createcolumns)) {
                push @createcolumns, $pkitem;
            }
        }
        my @allcolumns;
        foreach my $cname (@createcolumns) {
            push @allcolumns, $self->columnBasename($cname);
        }
        if(defined($self->{forceusercolumn})) {
            push @allcolumns, $self->{forceusercolumn};
        }

        my $instmt = "INSERT INTO "  . $self->{table} . " ( " .
                        join(', ', @allcolumns) . ") " .
                        "VALUES (" . join(',', ('?') x (scalar @allcolumns)) . ")";
        my $insth = $dbh->prepare_cached($instmt) or croak($dbh->errstr);
        my @inargs;
        if($self->{useserial}) {
            # Get primary key from database sequence
            my $seqsth = $dbh->prepare('SELECT ' . $self->{serial_nextval})
                    or croak($dbh->errstr);
            $seqsth->execute or croak($dbh->errstr);
            $newprimkey = $seqsth->fetchrow_array;
            $seqsth->finish;
        }
        foreach my $cname (@createcolumns) {
            my $column = $self->columnBasename($cname);
            my $multiarraymode = 0;
            if($cname ne $column) {
                $multiarraymode = 1;
            }
            my $arraycount = stripString($ua->{postparams}->{$column . '_count'} || '');
            if($arraycount eq '') {
                my $tmp = stripString($ua->{postparams}->{$column} || '');

                # Force "restrict" columns
                if(defined($self->{restrict})) {
                    foreach my $clauseitem (@{$self->{restrict}->{item}}) {
                        next if($clauseitem->{column} ne $column);
                        $tmp = $clauseitem->{value};
                        if($tmp =~ /USER/) {
                            $tmp =~ s/USER/$webdata{userData}->{user}/g;
                        }
                    }
                }

                if(contains($self->{editcolumntypes}->{$column}, $testtypes{boolean})) {
                    if($tmp eq '1' || $tmp =~ /^on$/i) {
                        $tmp = 1;
                    } else {
                        $tmp = 0;
                    }
                } elsif ($self->{editcolumntypes}->{$column} eq 'date') {
                    if($tmp eq '-- ::' || $tmp !~ /\d+/) {
                        # Compensate for datetimepicker empty template or when field is empty
                        $tmp = 'now';
                    }
                    if($tmp eq '') {
                        $tmp = 'now';
                    }
                    
                    # Check if this column defines a default value
                    if($tmp eq 'now') {
                        foreach my $item (@{$self->{edit}->{item}}) {
                            if(defined($item->{column}) && $item->{column} eq $column) {
                                if(defined($item->{default}) && $item->{default} ne '') {
                                    $tmp = $item->{default};
                                }
                                last;
                            }
                        }
                    }

                    $tmp = parseNaturalDate($tmp);
                    if( $self->{editcolumntypes}->{$column} eq 'dateonly') {
                        $tmp =~ s/\ .*//;
                    }
                } elsif ($self->{editcolumntypes}->{$column} eq 'number' || $self->{editcolumntypes}->{$column} eq 'slider') {
                    # make sure we always use the dot as a comma
                    $tmp =~ s/\,/./g;
                    if($tmp eq '') {
                        $tmp = 0;
                    } else {
                        $tmp = 0 + $tmp;
                    }
                } elsif($self->{editcolumntypes}->{$column} eq 'textarea' || $self->{editcolumntypes}->{$column} eq 'scripteditor') {
                    # Re-read unstripped value so we don't remove required line breaks
                    $tmp = $ua->{postparams}->{$column} || '';
                    $tmp =~ s/\r//g;
                    $tmp =~ s/\n{3,}/\n\n/g;
                    $tmp =~ s/\n+$//g;
                } elsif($self->{editcolumntypes}->{$column} eq 'editor') {
                    $tmp = $ua->{postparams}->{$column} || '';
                    $tmp =~ s/\n+$//g;
                } elsif($self->{editcolumntypes}->{$column} eq 'image') {
                    $tmp = $ua->{postparams}->{$column} || '';
                    my $newfname = $ua->{postparams}->{$column . '___new'} || '';
                    if($newfname ne '' && defined($ua->{files}->{$newfname})) {
                        $tmp = encode_base64($ua->{files}->{$newfname}->{data});
                    }
                }
                if($self->{editcolumnnullable}->{$column} && $tmp eq '') {
                    $tmp = undef;
                }
                if($self->{useserial} && contains($column, \@pkcols)) {
                    $tmp = $newprimkey;
                }

                # Make sure we don't have empty PK fields when useserial is false!
                if(!$self->{useserial} && contains($column, \@pkcols)) {
                    if(!defined($tmp) || $tmp eq '') {
                        $fieldsok = 0;
                        $errstr .= "Field $column can not be empty (PRIMARY KEY)! ";
                    }
                }

                push @inargs, $tmp;

            } else {
                my @inarray;
                for(my $i = 0; $i < $arraycount; $i++) {
                    my $tmp = '';
                    if($self->{editcolumntypes}->{$column} eq 'enumarray' || $self->{editcolumntypes}->{$column} eq 'enum') {
                        # Don't stripString when dealing with enums
                        $tmp = $ua->{postparams}->{$column . '_' . $i };
                    } else {
                        $tmp = stripString($ua->{postparams}->{$column . '_' . $i });
                    }

                    if($tmp eq '') {
                        if($multiarraymode || $self->{editcolumnnullable}->{$column}) {
                            $tmp = undef;
                        } else {
                            if($self->{editcolumntypes}->{$column} eq 'number' || $self->{editcolumntypes}->{$column} eq 'checkbox') {
                                $tmp = 0;
                            }
                        }
                    }

                    if($multiarraymode || $tmp ne '') {
                        push @inarray, $tmp;
                    }
                }
                push @inargs, \@inarray;
            }
        }

        if(defined($self->{forceusercolumn})) {
            push @inargs, $webdata{userData}->{user};
        }

        if($fieldsok) {
            if($insth->execute(@inargs)) {
                $dbh->commit;
                $okstr = "Created";
                $mode = "edit";
            } else {
                $errstr = $dbh->errstr;
                $dbh->rollback;
            }
        }
        if($self->{generateauditlog}) {
            $self->write_auditlog($webdata{userData}->{user}, 'create', @inargs);
        }
    } elsif($mode eq 'select') {
        if($primarykey ne '__NEW__') {
            # Don't save anything, just load
            $mode = 'edit';
            $isSelect = 1;
        } else {
            $mode = 'create';
            return (status  =>  403) unless $self->{cancreate};
        }
    }
    
    if($saveandclose) {
        return $self->get_list($ua);
    }

    my %colvalues;
    if($mode eq 'edit' && $errstr eq '') {
        if($isSelect) {
            if($primarykey eq '__NEW__') {
                @pkparts = ();
                foreach my $pkcol (@pkcols) {
                    push @pkparts, '__NEW__';
                }
            }
        } elsif($primarykey eq '__NEW__' && $self->{useserial}) {
            @pkparts = ($newprimkey);
        } else {
            @pkparts = ();
            foreach my $pkcol (@pkcols) {
                my $tmp = '';
                if(defined($ua->{postparams}->{$pkcol})) {
                    $tmp = stripString($ua->{postparams}->{$pkcol});
                }

                if(defined($self->{restrict})) {
                    foreach my $clauseitem (@{$self->{restrict}->{item}}) {
                        next if($clauseitem->{column} ne $pkcol);
                        $tmp = $clauseitem->{value};
                        if($tmp =~ /USER/) {
                            $tmp =~ s/USER/$webdata{userData}->{user}/g;
                        }
                    }
                }
                push @pkparts, $tmp;
            }
        }
        $primarykey = join('$$PKJ$$', @pkparts);

        # PostgreSQL returns the selected array element without index number, so make an alias that we can reverse-map after the select
        my @allcolumns = (@pkcols);
        my %colaliases;

        foreach my $item ((@{$self->{edit}->{item}})) {
            my $col = $self->getSelectColumns(\%colaliases, $item);
            if(defined($col)) {
                if(ref $col eq 'ARRAY') {
                    push @allcolumns, @{$col};
                } else {
                    push @allcolumns, $col;
                }
            }
        }
        my @filtered;
        foreach my $colspec (@allcolumns) {
            if(!contains($colspec, \@filtered)) {
                push @filtered, $colspec;
            }
        }

        my $selcolumns = join(', ', @filtered);

        my $selstmt = "SELECT " . $selcolumns . " FROM " . $self->{table} . " WHERE " . join(' = ? AND ', @pkcols) . " = ? ";

        my $selsth = $dbh->prepare_cached($selstmt)
                or croak($dbh->errstr);
        $selsth->execute(@pkparts) or croak($dbh->errstr);
        my $found = 0;
        while((my $line = $selsth->fetchrow_hashref)) {
            $found++;

            # Reverse-map the aliases
            foreach my $alias (sort keys %colaliases) {
                if(exists($line->{$alias})) {
                    #print STDERR "Reverse-mapping $alias\n";
                    $line->{$colaliases{$alias}} = $line->{$alias};
                    delete $line->{$alias};
                }
            }
            #foreach my $column (@{$self->{editcolumns}}, @{$self->{readonlycolumns}}) {
            foreach my $column (@allcolumns) {
                if(!defined($line->{$column})) {
                    $line->{$column} = '';
                }
                $colvalues{$column} = $line->{$column};
            }
        }
        $selsth->finish;
        $dbh->commit;
        if(!$found) {
            # Something went wrong, show the current list instead
            return $self->get_list($ua);
        }
    } elsif($primarykey eq '__NEW__') {
        foreach my $column (@{$self->{editcolumns}}, @{$self->{readonlycolumns}}) {
            my $tmp = '';

            if(defined($self->{restrict})) {
                foreach my $clauseitem (@{$self->{restrict}->{item}}) {
                    next if($clauseitem->{column} ne $column);
                    $tmp = $clauseitem->{value};
                    if($tmp =~ /USER/) {
                        $tmp =~ s/USER/$webdata{userData}->{user}/g;
                    }
                }
            }

            if(defined($forceFields) && defined($forceFields->{$column})) {
                $tmp = $forceFields->{$column};
            }

            if($tmp eq '') {
                foreach my $tmpitem (@{$self->{edit}->{item}}) {
                    if(defined($tmpitem->{column}) && $tmpitem->{column} eq $column && defined($tmpitem->{default})) {
                        $tmp = $tmpitem->{default};
                        last;
                    }
                }
            }

            $colvalues{$column} = $tmp;
        }
    } else {
        foreach my $column (@{$self->{editcolumns}}, @{$self->{readonlycolumns}}) {
            my $tmp = $ua->{postparams}->{$column} || '';

            if(defined($self->{restrict})) {
                foreach my $clauseitem (@{$self->{restrict}->{item}}) {
                    next if($clauseitem->{column} ne $column);
                    $tmp = $clauseitem->{value};
                    if($tmp =~ /USER/) {
                        $tmp =~ s/USER/$webdata{userData}->{user}/g;
                    }
                }
            }
            $colvalues{$column} = $tmp;
        }
    }

    my @editcolumns;
    foreach my $item (@{$self->{edit}->{item}}) {
        my $col = $self->formatEditColumn($primarykey, $item, \%colvalues, 0, {});
        if(defined($col)) {
            if(ref($col) eq 'ARRAY') {
                push @editcolumns, @{$col};
            } else {
                push @editcolumns, $col;
            }
        }
    }

    # un-bracketify column names so HTML and Javascript don't treat them as arrays
    for(my $idx = 0; $idx < scalar @editcolumns; $idx++) {
        if(defined($editcolumns[$idx]->{columnname})) {
            $editcolumns[$idx]->{columnname} =~ s/\[/XXXLEFTBRACKETXXX/g;
            $editcolumns[$idx]->{columnname} =~ s/\]/XXXRIGHTBRACKETXXX/g;
        }
    }

    $webdata{mode} = $mode;
    $webdata{columns} = \@editcolumns;
    $webdata{errstr} = $errstr;
    $webdata{okstr} = $okstr;
    $webdata{primary_key} = $primarykey;
    $webdata{UseTabs} = $self->{usetabs};
    $webdata{SelectedTab} = $selectedTab;
    $webdata{UsePrevNext} = $self->{useprevnext};
    
    if($self->{useprevnext}) {
        my ($prevkey, $nextkey) = $self->get_prevnext($ua, $primarykey);
        $webdata{prevprimarykey} = $prevkey;
        $webdata{nextprimarykey} = $nextkey;
        #print STDERR "PREV $prevkey and NEXT $nextkey found for $primarykey\n";
    }


    $dbh->rollback;
    my @headextrascripts;
    my @headextracss;
    if($self->{needcvceditor}) {
        push @headextrascripts, (
                                 '/static/cvceditor/cvceditor.js',
                                 '/static/cvceditor/adapters/jquery.js',
                                        );
        $webdata{EnableCVCEditor} = 1;
        $ua->{UseUnsafeCVCEditor} = 1;
    } else {
        $webdata{EnableCVCEditor} = 0;
    }

    if($self->{needscripteditor}) {
        push @headextrascripts, ('/static/codemirror/codemirror.js',
                                 '/static/codemirror/addon/edit/matchbrackets.js',
                                 '/static/codemirror/addon/comment/continuecomment.js',
                                 '/static/codemirror/addon/comment/comment.js',
                                 '/static/codemirror/addon/dialog/dialog.js',
                                 '/static/codemirror/addon/search/searchcursor.js',
                                 '/static/codemirror/addon/search/search.js',
                                 '/static/codemirror/addon/search/match-highlighter.js',
                                 '/static/codemirror/addon/search/matchesonscrollbar.js',
                                 '/static/codemirror/addon/edit/closebrackets.js',
                                 '/static/codemirror/mode/javascript/javascript.js',
                                 );
        push @headextracss, ('/static/codemirror/codemirror.css',
                             '/static/codemirror/addon/dialog/dialog.css',
                             '/static/codemirror/addon/search/matchesonscrollbar.css',
                             '/static/codemirror/theme/3024-night.css',
                             );
    }

    # Insert any extra Javascript that might have been defined in XML
    if($self->{useextraeditscript}) {
        push @headextrascripts, $self->{webpath} . '/pageeditscript.js';
    }

    $webdata{HeadExtraScripts} = \@headextrascripts;
    $webdata{HeadExtraCSS} = \@headextracss;

    my $usemasterlayout = 1;
    if($self->{mastertemplate} ne '') {
        $usemasterlayout = $self->{mastertemplate};
    }

    my $template = $self->{server}->{modules}->{templates}->get("listandedit/edit", $usemasterlayout, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub getSelectColumns($self, $colaliases, $item) {
    if($item->{type} eq 'multiarray') {
        my @allcolumns;
        foreach my $subitem (@{$item->{item}}) {
            my $col = $self->getSelectColumns($colaliases, $subitem);
            if(defined($col)) {
                if(ref $col eq 'ARRAY') {
                    push @allcolumns, @{$col};
                } else {
                    push @allcolumns, $col;
                }
            }
        }
        return \@allcolumns;
    }

    if($item->{type} eq 'newtab' || $item->{type} eq 'startsubtable' || $item->{type} eq 'endsubtable') {
        return;
    }

    my $colname = $self->columnBasename($item->{column});
    my $alias = '' . $colname;
    if($alias =~ /\[/ || $alias =~ /\./) {
        $alias =~ s/\[/xxopenbracketxx/g;
        $alias =~ s/\]/xxclosebracketxx/g;
        $alias =~ s/\./xxdotxx/g;
        $colaliases->{$alias} = $item->{column};
        $alias = $colname . ' AS ' . $alias;
    }
    return $alias;
}

sub formatEditColumn($self, $primarykey, $item, $colvalues, $multiarrayindex, $cache) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    if($item->{type} eq 'newtab') {
        my %column = (
            displayname  => $item->{header},
            displaytype  => $item->{type},
            tabname      => $item->{tabname},
            tablename    => $item->{tablename},
        );
        return \%column;
    }

    if($item->{type} eq 'startsubtable') {
        my %column = (
            displaytype  => $item->{type},
            header  => $item->{header},
        );
        return \%column;
    }
    if($item->{type} eq 'endsubtable') {
        my %column = (
            displaytype  => $item->{type},
            displayname => '',
        );

        return \%column;
    }

    if($item->{type} eq 'multiarray') {
        if($multiarrayindex) {
            # This should never happen, because it's BLOCKED by validation at startup!
            croak("Nested multiarray error");
        }
        # First, we need to find out how much real data lines we have
        my $count = 0;
        foreach my $subitem (@{$item->{item}}) {
            if(!defined($subitem->{column})) {
                next;
            }
            my $basename = $self->columnBasename($subitem->{column});
            if(defined($colvalues->{$basename})) {
                if(ref $colvalues->{$basename} ne 'ARRAY') {
                    # Hacky workaround for some edge cases when do for some reason don't get a proper array but a single value
                    if(ref $colvalues->{$basename} eq 'SCALAR' && $colvalues->{$basename} ne '') {
                        $colvalues->{$basename} = [$colvalues->{$basename}];
                    } else {
                        $colvalues->{$basename} = [];
                    }
                }
                my $newcount = scalar @{$colvalues->{$basename}};
                if($newcount > $count) {
                    $count = $newcount;
                }
            }
        }
        $count += $item->{spares}; # Add 'spares' empty rows (default: 5)

        my @edititems;

        # First thing we add is a "startsubtable" item
        {
            my %column = (
                displaytype  => 'startsubtable',
                header  => $item->{header},
            );

            push @edititems, \%column;
        }

        for(my $i = 0; $i < $count; $i++) {
            foreach my $subitem (@{$item->{item}}) {

                # WARNING, DO NOT CHANGE:
                # PostgreSQL uses 1-indexed arrays
                # We also use the index number to indicate that we ARE in multiarray mode, so
                # it can't start with zero either way!
                # Changing this to 0-indexed will break things in subtle ways and will lead to data loss.
                my $idx = $i + 1;

                my $col = $self->formatEditColumn($primarykey, $subitem, $colvalues, $idx, $cache);
                if(defined($col)) {
                    if(ref($col) eq 'ARRAY') {
                        push @edititems, @{$col};
                    } else {
                        push @edititems, $col;
                    }
                }

            }
        }
        foreach my $subitem (@{$item->{item}}) {
            # Add the "_count" hidden field so POST can read that as standard array
            {
                my %hiddenitem = (
                    displaytype => 'hidden',
                    columnname => $self->columnBasename($subitem->{column}) . '_count',
                    columnvalue => $count,
                );
                push @edititems, \%hiddenitem;
            }
        }
        
        # Add a "endsubtable" item to close up our subtable
        {
            my %column = (
                displaytype  => 'endsubtable',
                displayname => '',
            );

            push @edititems, \%column;
        }

        return \@edititems;
    }


    my $colname = '' . $item->{column};
    my $colbasename = '' . $item->{column};
    if($multiarrayindex) {
        $colname = $self->columnAddHTMLIndex($colname, $multiarrayindex - 1);
        $colbasename = $self->columnBasename($colbasename);
    }

    my $realvalue;
    if($multiarrayindex) {
        if(!defined($colvalues->{$colbasename}->[$multiarrayindex - 1])) {
            $realvalue = '';
        } else {
            $realvalue = $colvalues->{$colbasename}->[$multiarrayindex - 1];
        }
    } else {
        if(!defined($colvalues->{$colname})) {
            $realvalue = '';
        } else {
            $realvalue = $colvalues->{$colname};
        }
    }

    my %column = (
        displayname  => $item->{header},
        displaytype  => $item->{type},
        columnname   => $colname,
        columnvalue  => $realvalue,
        goto         => 0,
        linebreak  => $item->{linebreak},
        columnbreak  => $item->{columnbreak},
    );

    if($column{displaytype} eq 'checkbox') {
        $column{callback} = $item->{callback};
        $column{realvalue} = $item->{realvalue};
        $column{realinactivevalue} = $item->{realinactivevalue};
        $column{delete} = $item->{delete};
    }

    if($column{displaytype} eq 'date') {
        $column{columnvalue} =~ s/\..*//;
        if(defined($item->{default}) && $item->{default} ne '' && $item->{default} eq $column{columnvalue}) {
            # Display default value as empty
            $column{columnvalue} = '';
        }
    }
    if($column{displaytype} eq 'dateonly') {
        $column{columnvalue} =~ s/\ .*//;
        if(defined($item->{default}) && $item->{default} ne '' && $item->{default} eq $column{columnvalue}) {
            # Display default value as empty
            $column{columnvalue} = '';
        }
    }

    if($column{displaytype} eq 'text') {
        $column{size} = $item->{size};
        $column{maxlength} = $item->{maxlength};
    }

    if($column{displaytype} eq 'timeonly') {
        if($column{columnvalue} =~ /\:\d\d\:/) {
            # Has seconds, remove them
            $column{columnvalue} =~ s/\:\d\d$//;
        }
    }
    
    if($column{displaytype} eq 'image') {
        #$column{displaytype} = 'text';
        if($column{columnvalue} ne '') {
            $column{imagedata} = 'data:image/png;base64,' . $column{columnvalue};
        } else {
            $column{imagedata} = '';
        }
    }

    if($column{displaytype} eq 'imagedisplay') {
        #$column{displaytype} = 'text';
        if($column{columnvalue} ne '') {
            $column{imagedata} = 'data:image/png;base64,' . $column{columnvalue};
        } else {
            $column{imagedata} = '';
        }
    }
    
    if($column{displaytype} eq 'editor') {
        # CVCEditor 4.x has a very fundamental bug regarding <code> tags:
        # It still parses encoded characters like '&lt;' to '<', which
        # completly breaks the syntax highlighter
        #
        # There is a crude workaround of encoding every '&' to '&amp;'.
        # So, '&lt;' becomes '&amp;lt;'. Stupid, but it seems to work.
        # Let's do this by first checking if we HAVE any code tags (if not,
        # we can go on normally). If we do, split the string on the end "</code>"
        # tags, then on the code tags '<code .?>', reencode the '&', add
        # it all up again with the now missing code tags and we're sort of done.
        # Messy, to say the least.
        if($column{columnvalue} =~ /\<\/code\>/) {
            # Got ourselfs some code tags.
            my $newval = '';
            my @parts = split/\<\/code\>/, $column{columnvalue};
            foreach my $part (@parts) {
                if($part =~ /(.*)(\<code.*?\>)(.*)/si) {
                    my ($noncode, $tag, $code) = ($1, $2, $3);
                    $code =~ s/\&/\&amp\;/g;
                    $newval .= $noncode . $tag . $code . '</code>';
                } else {
                    # "the rest"
                    $newval .= $part;
                }
            }
            $column{columnvalue} = $newval;
        }
    }

    if($column{displaytype} =~ /^textarea/ || $column{displaytype} eq 'scripteditor') {
        $column{cols} = $item->{cols};
        $column{rows} = $item->{rows};
        $column{charcount} = $item->{charcount};
    }

    $column{mustfield} = $item->{mustfield};

    if($column{displaytype} eq 'slider' || $column{displaytype} eq 'number') {
        if(!defined($column{columnvalue}) || $column{columnvalue} eq '' || $column{columnvalue} < $item->{value_min}) {
            $column{columnvalue} = $item->{value_min};
        } elsif($column{columnvalue} > $item->{value_max}) {
            $column{columnvalue} = $item->{value_max};
        }
    }

    if($primarykey eq '__NEW__' && defined($item->{createtype})) {
        $column{displaytype} = $item->{createtype};
    }

    foreach my $optionname (qw[enumtable enumvalue value_min value_max step parentcolumn hasdecimal]) {
        if(defined($item->{$optionname})) {
            $column{$optionname} = $item->{$optionname};
        }
    }

    # #### ENUM ####
    if($item->{type} eq 'enum') {
        my $extracolumn = '';
        my $hasdescription = 0;
        if(defined($item->{showdescription})) {
            $extracolumn = ', ' . $item->{showdescription} . ' AS selectorenumdescription ';
            $hasdescription = 1;
        }

        my $where = '';
        if(defined($item->{enumwhere})) {
            $where = ' WHERE ' . $item->{enumwhere} . ' ';
        }

        my $eselstmt = 'SELECT ' . $item->{enumcolumn} . ' AS selectorenumvalue ' .
                        $extracolumn .
                        ' FROM ' . $item->{enumtable} .
                        $where .
                        ' ORDER BY ' . $item->{enumcolumn};

        my $cachekey = $self->makeCacheKey($hasdescription, $eselstmt);
        if(!defined($cache->{$cachekey})) {
            my @enumlines;
            my $eselsth = $dbh->prepare_cached($eselstmt)
                    or croak($dbh->errstr);
            $eselsth->execute or croak($dbh->errstr);
            while((my $eline = $eselsth->fetchrow_hashref)) {
                $eline->{hasdescription} = $hasdescription;
                push @enumlines, $eline;
            }
            $eselsth->finish;
            $cache->{$cachekey} = \@enumlines;
        }

        my @enum_values = @{$cache->{$cachekey}};
        if($item->{nullable}) {
            my %emptyval = (
                selectorenumvalue   => '',
                hasdescription      => 0,
            );
            unshift @enum_values, \%emptyval;
        }

        $column{enum_values} = \@enum_values;
        $column{searchable} = $item->{searchable};
        $column{extendable} = $item->{extendable};
        $column{colorselector} = $item->{colorselector};
        $column{descriptiononly} = $item->{descriptiononly};
        $column{multilanguage} = $item->{multilanguage};
    }

    # #### SUB-ENUM ####
    if($item->{type} eq 'subenum') {
        my $extracolumn = '';
        my $hasdescription = 0;
        if(defined($item->{showdescription})) {
            $extracolumn = ', ' . $item->{showdescription} . ' AS selectorenumdescription ';
            $hasdescription = 1;
        }
        my $eselstmt = 'SELECT ' . $item->{enumparentcolumn} . ' AS selectorenumparentvalue, ' .
                       $item->{enumcolumn} . ' AS selectorenumvalue ' .
                       $extracolumn .
                       ' FROM ' . $item->{enumtable} .
                       ' ORDER BY ' . $item->{enumparentcolumn} . ', ' . $item->{enumcolumn};

        my $cachekey = $self->makeCacheKey($hasdescription, $eselstmt);
        if(!defined($cache->{$cachekey})) {
            my @enumlines;
            my $eselsth = $dbh->prepare_cached($eselstmt)
                    or croak($dbh->errstr);
            $eselsth->execute or croak($dbh->errstr);

            my $currentparent;
            my @enums = ();
            while((my $eline = $eselsth->fetchrow_hashref)) {
                $eline->{hasdescription} = $hasdescription;

                if(!defined($currentparent)) {
                    $currentparent = $eline->{selectorenumparentvalue};
                    push @enums, $eline;
                } elsif($currentparent ne $eline->{selectorenumparentvalue}) {
                    my @tmp = @enums;
                    my %fullline = (
                        parentenumvalue     => $currentparent,
                        subenums            => \@tmp,
                    );
                    push @enumlines, \%fullline;
                    $currentparent = $eline->{selectorenumparentvalue};
                    @enums = ();
                    push @enums, $eline;
                } else {
                    push @enums, $eline;
                }
            }
            $eselsth->finish;

            if(@enums) {
                my @tmp = @enums;
                my %fullline = (
                    parentenumvalue     => $currentparent,
                    subenums            => \@tmp,
                );
                push @enumlines, \%fullline;
            }

            $cache->{$cachekey} = \@enumlines;
        }

        my @enum_values = @{$cache->{$cachekey}};

        $column{enum_values} = \@enum_values;
        $column{enum_values_json} = encode_base64(encode_json \@enum_values, '');
        $column{searchable} = $item->{searchable};
        $column{descriptiononly} = $item->{descriptiononly};
    }
    
    # #### ENUMARRAY ####
    if($item->{type} eq 'enumarray') {
        my $extracolumn = '';
        my $hasdescription = 0;
        if(defined($item->{showdescription})) {
            $extracolumn = ', ' . $item->{showdescription} . ' AS selectorenumdescription ';
            $hasdescription = 1;
        }

        my $where = '';
        if(defined($item->{enumwhere})) {
            $where = ' WHERE ' . $item->{enumwhere} . ' ';
        }

        my $eselstmt = 'SELECT ' . $item->{enumcolumn} . ' AS selectorenumvalue ' .
                       $extracolumn .
                       ' FROM ' . $item->{enumtable} .
                       $where .
                       ' ORDER BY ' . $item->{enumcolumn};

        my $cachekey = $self->makeCacheKey($hasdescription, $eselstmt);
        if(!defined($cache->{$cachekey})) {
            my @enumlines;
            print STDERR "STMT: $eselstmt\n";
            my $eselsth = $dbh->prepare_cached($eselstmt)
                    or croak($dbh->errstr);
            $eselsth->execute or croak($dbh->errstr);
            while((my $eline = $eselsth->fetchrow_hashref)) {
                $eline->{hasdescription} = $hasdescription;
                push @enumlines, $eline;
            }
            $eselsth->finish;
            $cache->{$cachekey} = \@enumlines;
        }

        my @enum_values = @{$cache->{$cachekey}};
        {
            # enum array ALWAYS has a "nullable" row"
            my %emptyval = (
                selectorenumvalue   => '',
                hasdescription      => 0,
            );
            unshift @enum_values, \%emptyval;
        }

        $column{enum_values} = \@enum_values;
        $column{searchable} = $item->{searchable};
        $column{colorselector} = $item->{colorselector};
        $column{descriptiononly} = $item->{descriptiononly};
        $column{multilanguage} = $item->{multilanguage};
        if(!defined($column{columnvalue}) || ref $column{columnvalue} ne 'ARRAY') {
            $column{columnvalue} = [];
        }
        for(1..$item->{spares}) {
            push @{$column{columnvalue}}, '';
        }
    }

    if(defined($item->{goto})) {
        $column{goto} = 1;
        $column{gotourl} = $item->{goto};

        if($column{gotourl} =~ /\[(.*)\]/) {
            my $tmp = $1;
            my $dest = $primarykey;
            if($tmp ne 'PK') {
                $dest = $colvalues->{$colname} || ''
            }

            $dest = encode_uri($dest);
            $column{gotourl} =~ s/\[.*\]/$dest/;
        }
    }

    return \%column;
}

sub makeCacheKey($self, $hasdescription, $stmt) {
    $stmt =~ s/\n/ /g;
    $stmt =~ s/\ +/ /g;
    $stmt .= '#' . $hasdescription;

    return sha1_hex($stmt);
}


sub get_autosave($self, $ua) {

    if($self->{listonly}) {
        return (status => 403); # Forbidden
    }


    my %result = $self->get_edit($ua);

    if($result{status} == 200) {
        return (status => 204);
    }

    return (status => 500);

}

sub write_auditlog($self, $username, $mode, @data) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $insth = $dbh->prepare_cached("INSERT INTO auditlog (worker_name, module_name, username, logtext, extrainfo)
                                        VALUES ('webgui', ?, ?, ?, ?)")
            or croak($dbh->errstr);
    my @newdata;
    foreach my $field (@data) {
        if(ref $field eq 'ARRAY') {
            push @newdata, join('|', $field);
        } else {
            push @newdata, $field;
        }
    }
    if(!$insth->execute($self->{modname}, $username, $mode . " in " . $self->{table}, \@newdata)) {
        print STDERR 'Auditlog failed: ', $dbh->errstr, "\n";
        $dbh->rollback;
    } else {
        $dbh->commit;
    }

    return;
}

sub columnAddIndex($self, $colname, $idx) {
    my $newcolname = '' . $colname;
    if($newcolname !~ /\[\]/) {
        croak("Column $newcolname is not an array column (missing empty array marker \[\] suitable for multiarray mode");
    }
    $newcolname =~ s/\[\]/\[$idx\]/;
    return $newcolname;
}

sub columnAddHTMLIndex($self, $colname, $idx) {
    my $newcolname = '' . $colname;
    if($newcolname !~ /\[\]/) {
        croak("Column $newcolname is not an array column (missing empty array marker \[\] suitable for multiarray mode");
    }
    $newcolname =~ s/\[\]/_$idx/;
    return $newcolname;
}

sub columnBasename($self, $colname) {
    my $newcolname = '' . $colname;
    $newcolname =~ s/\[\]//;
    return $newcolname;
}

1;
__END__

=head1 NAME

PageCamel::Web::ListAndEdit -

=head1 SYNOPSIS

  use PageCamel::Web::ListAndEdit;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 reload



=head2 getColumnType



=head2 get



=head2 get_list



=head2 get_lines



=head2 get_edit



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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
