package PageCamel::Helpers::AutoDialogs;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use PageCamel::Helpers::Translator;
use HTML::Entities;
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Strings;

sub new {
    my ($class) = @_;
    my $self = bless {
    }, $class;

    $self->{markup} = "";
    $self->{js} = "";
    $self->{jqueryinit} = "";
    $self->{translations} = {};
    $self->{count} = 0;

    return $self;
}

sub addDialog {
    my ($self, $config, $fname) = @_;

    if($config->{type} eq 'notification') {
        return $self->notification($config);
    } elsif($config->{type} eq 'simpleform') {
        return $self->simpleform($config);
    } elsif($config->{type} eq 'modechangeform') {
        return $self->modechangeform($config);
    } else {
        croak("Unknown AutoDialog type " . $config->{type} . "in $fname");
    }
}


sub notification {
    my ($self, $data) = @_;

    my $title = $data->{title} || 'UNDEFINED';
    my $text = $data->{text} || 'UNDEFINED';
    my $action = $data->{confirm} || 'OK';
    my $trquoteshortname = $self->elemNameQuote(lc $action);
    my $trquotelongname = 'ttvars.trquote.Autodialog' . $trquoteshortname;
    
    $self->{translations}->{$trquoteshortname} = $action;
    
    if(!defined($data->{name})) {
        croak("undefined value name, can't continue");
    }
    my $name = $data->{name};
    my $icon = $data->{icon};
    my $picture = $data->{picture} || '';
    if($picture ne '') {
        $picture = "<br/><p align=\"center\"><img class=\"pagecameldialogimageborder\" src=\"$picture\"/></p>";
    }

    my $markup = <<"ENDMARKUP";
<!-- AutoDialog markup for $name -->
<div id="dialog-$name" title="\[\% tr.trquote(\"$title\") \%\]">
    <p><span class="ui-icon ui-icon-$icon pagecameldialoglayout"></span>\[\% tr.trquote(\"$text\") \%\]</p>$picture
</div>

ENDMARKUP


    my $js = <<"ENDJS";
// AutoDialog wrapper
function $name(formname) {
    \$( "#dialog-$name" ).dialog("open");
    return false;
}

ENDJS

    my $jquery = <<"ENDJQUERY";
// AutoDialog initializer
\$( "#dialog-$name" ).dialog({
        autoOpen: false,
        resizable: false,
        modal: true,
        width: 400,
        height: 600,
        show: {
            effect: "puff",
            duration: 200
        },
        hide: {
            effect: "puff",
            duration: 200
        },
        buttons: [
            {
                text: $trquotelongname,
                click: function() {
                    \$( this ).dialog( "close" );
                }
            }
        ]
    });

ENDJQUERY

    $self->{forms}->{markup} .= $markup;
    $self->{forms}->{js} .= $js;
    $self->{forms}->{jqueryinit} .= $jquery;

    $self->{count}++;

    return '';
}


sub simpleform {
    my ($self, $data) = @_;

    my $title = $data->{title} || 'UNDEFINED';
    my $text = $data->{text} || 'UNDEFINED';
    my $action = $data->{confirm} || 'OK';
    my $cancel = $data->{cancel} || 'Cancel';
    
    my $trquoteactionshortname = $self->elemNameQuote(lc $action);
    my $trquoteactionlongname = 'ttvars.trquote.Autodialog' . $trquoteactionshortname;
    my $trquotecancelshortname = $self->elemNameQuote(lc $cancel);
    my $trquotecancellongname = 'ttvars.trquote.Autodialog' . $trquotecancelshortname;
    
    $self->{translations}->{$trquoteactionshortname} = $action;
    $self->{translations}->{$trquotecancelshortname} = $cancel;
    
    if(!defined($data->{name})) {
        croak("undefined value name, can't continue");
    }
    my $name = $data->{name};
    my $icon = $data->{icon};
    my $picture = $data->{picture} || '';
    if($picture ne '') {
        $picture = "<br/><p align=\"center\"><img class=\"pagecameldialogimage\" src=\"$picture\"/></p>";
    }

my $markup = <<"ENDMARKUP";
<!-- AutoDialog markup for $name -->
<div id="dialog-$name" title="\[\% tr.trquote(\"$title\") \%\]">
    <p><span class="ui-icon ui-icon-$icon pagecameldialoglayout"></span>\[\% tr.trquote(\"$text\") \%\]</p>
</div>

ENDMARKUP


    my $js = <<"ENDJS";
// AutoDialog wrapper
function $name(formname) {
    if(!formname) {
        alert("No formname given in call to " + $name);
        return false;
    }
    autodialogs_form = formname;
    \$( "#dialog-$name" ).dialog("open");
    return false;
}

ENDJS

    my $jquery = <<"ENDJQUERY";
// AutoDialog initializer
\$( "#dialog-$name" ).dialog({
        autoOpen: false,
        resizable: false,
        modal: true,
        width: 400,
        height: 600,
        show: {
            effect: "puff",
            duration: 200
        },
        hide: {
            effect: "puff",
            duration: 200
        },
        buttons: [
            {
                text: $trquoteactionlongname,
                click: function() {
                    \$( this ).dialog( "close" );
                    document.forms[autodialogs_form].submit();
                }
            },
            {
                text: $trquotecancellongname,
                click: function() {
                    autodialogs_form = "";
                    \$( this ).dialog( "close" );
                }
            }
        ]
    });

ENDJQUERY

    $self->{forms}->{markup} .= $markup;
    $self->{forms}->{js} .= $js;
    $self->{forms}->{jqueryinit} .= $jquery;

    $self->{count}++;

    return '';
}

sub modechangeform {
    my ($self, $data) = @_;

    my $title = $data->{title} || 'UNDEFINED';
    my $text = $data->{text} || 'UNDEFINED';
    my $action = $data->{confirm} || 'OK';
    my $cancel = $data->{cancel} || 'Cancel';

    my $trquoteactionshortname = $self->elemNameQuote(lc $action);
    my $trquoteactionlongname = 'ttvars.trquote.Autodialog' . $trquoteactionshortname;
    my $trquotecancelshortname = $self->elemNameQuote(lc $cancel);
    my $trquotecancellongname = 'ttvars.trquote.Autodialog' . $trquotecancelshortname;
    
    $self->{translations}->{$trquoteactionshortname} = $action;
    $self->{translations}->{$trquotecancelshortname} = $cancel;
    
    if(!defined($data->{name})) {
        croak("undefined value name, can't continue");
    }
    if(!defined($data->{mode})) {
        croak("undefined value mode, can't continue");
    }

    my $name = $data->{name};
    my $mode = $data->{mode};
    my $icon = $data->{icon} || 'help';
    my $picture = $data->{picture} || '';
    if($picture ne '') {
        $picture = "<br/><p align=\"center\"><img class=\"pagecameldialogimage\" src=\"$picture\"/></p>";
    }

    my $markup = <<"ENDMCMARKUP";
<!-- AutoDialog modechange markup for $name -->
<div id="dialog-$name" title="\[\% tr.trquote(\"$title\") \%\]">
    <p><span class="ui-icon ui-icon-$icon pagecameldialoglayout"></span>\[\% tr.trquote(\"$text\") \%\]</p>$picture
</div>

ENDMCMARKUP

    my $js = <<"ENDMCJS";
// AutoDialog modechange wrapper
function $name(formname, elemid) {
    if(!formname) {
        alert("No formname given in call to " + $name);
        return false;
    }
    if(!elemid) {
        alert("No elemid given in call to " + $name);
        return false;
    }
    autodialogs_form = formname;
    autodialogs_elem = elemid;
    \$( "#dialog-$name" ).dialog("open");
    return false;
}

ENDMCJS

    my $jquery = <<"ENDMCJQUERY";
// AutoDialog initializer
\$( "#dialog-$name" ).dialog({
        autoOpen: false,
        resizable: false,
        modal: true,
        width: 400,
        height: 600,
        show: {
            effect: "puff",
            duration: 200
        },
        hide: {
            effect: "puff",
            duration: 200
        },
        buttons: [
            {
                text: $trquoteactionlongname,
                click: function() {
                    \$( this ).dialog( "close" );
                    var modeElem = document.getElementById(autodialogs_elem);
                    modeElem.value = "$mode";
                    document.forms[autodialogs_form].submit();
                }
            },
            {
                text: $trquotecancellongname,
                click: function() {
                    autodialogs_form = "";
                    autodialogs_elem = "";
                    \$( this ).dialog( "close" );
                }
            }
        ]
    });

ENDMCJQUERY

    $self->{forms}->{markup} .= $markup;
    $self->{forms}->{js} .= $js;
    $self->{forms}->{jqueryinit} .= $jquery;

    $self->{count}++;

    return '';
}

sub getHTML {
    my ($self, $context) = @_;

    if(!$self->{count}) {
        return "";
    }
    
    my $translate = '';
    foreach my $key (keys %{$self->{translations}}) {
        $translate .= 'data-trquote-autodialog' . $key . '="[% tr.trquote("' . $self->{translations}->{$key} . '") %]" ';
    }
    if($translate ne '') {
        $translate = '<span id="autodialogstemplatedataset" ' . $translate . '></span>';
    }

    return $translate . "\n" . $self->{forms}->{markup} . "\n";
}

sub getJS {
    my ($self, $context) = @_;

    if(!$self->{count}) {
        return "";
    }

    return "\n" .
            "var autodialogs_form = '';var autodialogs_elem = '';\n" .
            "function JSinitTTDialogs() {\n" .
                $self->{forms}->{jqueryinit} . "\n" .
            "}\n" .
            $self->{forms}->{js} . "\n";
}

sub tr { ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self, $data) = @_;

    return $data if($data eq '');

    my $lang = $self->getLang;
    my $trans = tr_translate($lang, $data);

    return $trans;
}

sub quote {
    my ($self, $data) = @_;

    my $quoted = encode_entities($data, "'<>&\"\n");
    $quoted =~ s/ä/&auml;/;
    $quoted =~ s/ö/&ouml;/;
    $quoted =~ s/ü/&uuml;/;
    $quoted =~ s/Ä/&Auml;/;
    $quoted =~ s/Ö/&Ouml;/;
    $quoted =~ s/Ü/&Uuml;/;
    $quoted =~ s/ß/&szlig;/;

    return $quoted;
}

sub trquote {
    my ($self, $data) = @_;

    return $self->quote($self->tr($data));
}

sub elemNameQuote {
    my ($self, $data) = @_;
    return $self->quote(PageCamel::Helpers::Strings::elemNameQuote($data));
}


1;
__END__

=head1 NAME

PageCamel::Web::TT::AutoDialogs -

=head1 SYNOPSIS

  use PageCamel::Web::TT::AutoDialogs;



=head1 DESCRIPTION



=head2 new



=head2 notification



=head2 simpleform



=head2 modechangeform



=head2 getForms




=head2 quote



=head2 elemNameQuote



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
