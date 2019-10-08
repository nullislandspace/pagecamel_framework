package PageCamel::Web::Users::Login;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use Crypt::Digest::SHA256 qw[sha256_hex];
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Passwords qw(verify_password gen_textsalt);
use PageCamel::Helpers::UserAgent qw[simplifyUA];
use PageCamel::Helpers::URI qw[decode_uri_path];
use MIME::Base64;
use Data::Dumper;

use Readonly;

Readonly my $TESTRANGE => 1_000_000;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    #$self->{password_prefix} = "CARNIVORE::";
    #$self->{password_postfix} = "# or 1984";

    $self->{basicauth_prefix_salt} = gen_textsalt();
    $self->{basicauth_middle_salt} = gen_textsalt();
    $self->{basicauth_postfix_salt} = gen_textsalt();

    my %paths;
    $self->{paths} = \%paths;

    if(!defined($self->{httpsonlycookies}) || $self->{isDebugging}) {
        $self->{httpsonlycookies} = 0;
    }

    if(!defined($self->{memcache})) {
        croak("No memcache defined for module " . $self->{modname});
    }

    if(!defined($self->{disable_firewall})) {
        $self->{disable_firewall} = 0;
    }

    return $self;
}

sub register {
    my $self = shift;

    $self->register_webpath($self->{login}->{webpath}, "get_login");

    $self->register_webpath($self->{logout}->{webpath}, "get_logout");
    $self->register_webpath($self->{sessionrefresh}->{webpath}, "get_sessionrefresh", 'GET', 'POST');
    $self->register_logstart("preauthcleanup");
    $self->register_authcheck("prefilter");
    $self->register_postfilter("postfilter");
    $self->register_defaultwebdata("get_defaultwebdata");

    if(defined($self->{switchtouser}->{webpath})) {
        $self->register_webpath($self->{switchtouser}->{webpath}, "get_switchtouser", 'GET');
    }
    if(defined($self->{switchfromuser}->{webpath})) {
        $self->register_webpath($self->{switchfromuser}->{webpath}, "get_switchfromuser", 'GET');
    }

    return;
}

sub crossregister {
    my ($self) = @_;

    $self->register_public_url($self->{login}->{webpath});
    $self->register_public_url($self->{logout}->{webpath});

    if(defined($self->{register}->{webpath})) {
        $self->register_public_url($self->{register}->{webpath});
    }

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $type = ref $memh;

    if($type !~ /ClacksCache$/ && $type !~ /ClacksCachePg$/) {
        croak("memcache type is $type but needs to be of type ClacksCache or ClacksCachePg in module " . $self->{modname});
    }

    return;
}

sub get_logout {
    my ($self, $ua) = @_;

    my $session = $ua->{cookies}->{"pagecamel-session"};
    if(!$self->validateSession($session, $ua)) {
        return (status      => 303,
                location    => $self->{login}->{webpath},
                type        => "text/html",
                data         => "<html><body><h1>Please login</h1><br>" .
                                "If you are not automatically redirected, click " .
                                "<a href=\"" . $self->{login}->{webpath} . "\">here</a>.</body></html>",
                );
    }

    $self->deleteSession($session);

    $self->{cookie} = $self->create_cookie($ua,
                                           "name" => "pagecamel-session",
                                            "value" => "NONE",
                                            "httponly" => 1,
                                            "secure" => $self->{httpsonlycookies},
                                            "location" => '/',
                                            "samesite" => 'strict',
                                            );

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{logout}->{pagetitle},
        BackLink    =>  $self->{login}->{webpath},
    );

    my $template = $self->{server}->{modules}->{templates}->get("users/logout", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  303,
            location => '/', # Automatically restart everything as if user just called up the domain (handle all the guest user stuff)
            type    => "text/html",
            data    => $template);
}

sub get_login {
    my ($self, $ua) = @_;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{login}->{pagetitle},
        username    =>  $ua->{postparams}->{'username'} || '',
        password    =>  $ua->{postparams}->{'password'} || '',
        PostLink    =>  $self->{login}->{webpath},
    );

    # Force lowercase username
    $webdata{username} = lc $webdata{username};

    my $mode = $ua->{postparams}->{'mode'} || 'username';
    my $host_addr = $ua->{remote_addr};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $viewh = $self->{server}->{modules}->{$self->{views}};

    if($webdata{username} ne '' && $webdata{password} ne '') {

        my $pwok = verify_password($dbh, $webdata{username}, $webdata{password});

        my $tempsessionid = $ua->{postparams}->{'tempsessionid'} || '';
        my $tempclientid = $ua->{postparams}->{'tempclientid'} || '';
        for(my $i = 1; $i < 20; $i++) {
            $tempsessionid = sha256_hex(substr($tempsessionid, 1, 12) . $i);
        }
        $tempsessionid = uc substr($tempsessionid, 3, 8);
        my $clidmsg = '';
        if($tempsessionid ne $tempclientid) {
            $pwok = 0;
            $clidmsg = ' (CLIDFAIL)';
        }

        if(!$pwok) {
            $self->firewall_log_loginfailure($ua);
        }

        my $toomanyfails = 0;
        if(!$self->firewall_check_loginfailure($ua)) {
            $webdata{statustext} = "Too many login failures";
            $webdata{statuscolor} = "errortext";
            $reph->auditlog($self->{modname}, "Login failed for IP " . $ua->{remote_addr} . " (too many retries)");
            goto finishlogin;
        } elsif(!$pwok) {
            $webdata{statustext} = "Login error";
            $webdata{statuscolor} = "errortext";
            $reph->auditlog($self->{modname}, "Login failed for user " . $webdata{username} . $clidmsg, $webdata{username});
            goto finishlogin;
        } else {
            $reph->auditlog($self->{modname}, "Login success for user " . $webdata{username}, $webdata{username});
        }

        # Delete the old session if any
        {
            my $oldsession = $ua->{cookies}->{"pagecamel-session"};
            if(defined($oldsession) && $oldsession =~ /^3SESSION/) {
                $self->deleteSession($oldsession);
            }
        }

        my %html5;
        my %cleartext = (
            -1  => 'unknown',
            0   => 'disabled',
            1   => 'enabled',
        );

        foreach my $htmlfeature (qw[canvas websockets localstorage sessionstorage sessionhistory webworkers sharedworkers draganddrop xmlhttprequest websql]) {
            my $tmp = $ua->{postparams}->{'html5_' . $htmlfeature};
            if(!defined($tmp)) {
                $tmp = -1;
            }
            $html5{$htmlfeature} = $tmp;
            #print STDERR " *** $htmlfeature $cleartext{$tmp}\n";
        }


        my $sth = $dbh->prepare_cached("SELECT username, email_addr,
                                       first_name, last_name,
                                       (next_password_change < now() AND password_can_expire = true) as require_password_change,
                                       company_name
                                       FROM users
                                WHERE username = ?")
                    or croak($dbh->errstr);

        $sth->execute($webdata{username});


        my %user;
        while((my $line = $sth->fetchrow_hashref)) {
            $user{username} = $line->{username};
            $user{email_addr} = $line->{email_addr};
            $user{first_name} = $line->{first_name};
            $user{last_name} = $line->{last_name};
            $user{company} = $line->{company_name};
            $user{require_password_change} = $line->{require_password_change};
            last;
        }
        $sth->finish;
        $user{html5} = \%html5;


        my @dbRights;
        my $rightssth = $dbh->prepare_cached("SELECT * FROM users_permissions
                                             WHERE username = ?
                                             AND has_access = true
                                             ORDER BY permission_name")
                or croak($dbh->errstr);
        $rightssth->execute($user{username}) or croak($dbh->errstr);
        while((my $right = $rightssth->fetchrow_hashref)) { ## no critic (NamingConventions::ProhibitAmbiguousNames)
            my $restrict = 0;
            foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
                if(defined($ur->{restrict}) && $right->{permission_name} eq $ur->{db}) {
                    $restrict = 1;
                    last;
                }
            }
            if(!$restrict) {
                push @dbRights, $right->{permission_name};
            }
        }
        $rightssth->finish;
        foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
            if(defined($ur->{restrict}) && contains($user{username}, $ur->{restrict})) {
                push @dbRights, $ur->{db};
            }
        }
        $user{rights} = \@dbRights;

        my $upsth = $dbh->prepare_cached("UPDATE users
                                         SET last_login_time = now(),
                                         last_login_ip = ?
                                         WHERE username = ?")
                or croak($dbh->errstr);
        $upsth->execute($host_addr, $user{username}) or croak($dbh->errstr);
        $upsth->finish;
        $dbh->commit;

        my $session = $self->createSession($ua, $user{username});

        if($user{require_password_change}) {
            $user{startpage} = $self->{pwchange};
            $user{realstartpage} = $viewh->getstarturl(\@dbRights);
        } else {
            $user{startpage} = $viewh->getstarturl(\@dbRights);
            $user{realstartpage} = $user{startpage};
        }

        $self->{server}->{modules}->{$self->{memcache}}->set($session, \%user);
        $webdata{statustext} = "Login ok, please wait...!";
        $webdata{statuscolor} = "oktext";
        $webdata{SetDocumentHREF} = $user{startpage};

        $self->{cookie} = $self->create_cookie($ua,
                                "name" => "pagecamel-session",
                                "value" => "$session",
                                "expires" => $self->{expires},
                                "httponly" => 1,
                                "secure" => $self->{httpsonlycookies},
                                "location" => '/',
                                "samesite" => 'strict',
                                );
        $self->{currentSessionID} = $session;

    }

    finishlogin:
    $webdata{password} = "";

    # Robby detection ("romotest")
    my @extrascripts = ('/static/sha256.js');
    $webdata{HeadExtraScripts} = \@extrascripts;
    $webdata{tempsessionid} = PageCamel::Helpers::Passwords::gen_textsalt();
    $webdata{tempclientid} = PageCamel::Helpers::Passwords::gen_textsalt();

    my $template = $self->{server}->{modules}->{templates}->get("users/login", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub getAutologin {
    my ($self, $ua) = @_;

    my $host_addr = $ua->{remote_addr};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $viewh = $self->{server}->{modules}->{$self->{views}};

    # Delete the old session if any
    {
        my $oldsession = $ua->{cookies}->{"pagecamel-session"};
        if(defined($oldsession) && $oldsession =~ /^3SESSION/) {
            $self->deleteSession($oldsession);
        }
    }

    my %html5;
    my %cleartext = (
        -1  => 'unknown',
        0   => 'disabled',
        1   => 'enabled',
    );

    #$reph->auditlog($self->{modname}, "Autologin for GUEST user " . $self->{autologin}->{username});

    # Fake HTML5 features to "unknown"
    foreach my $htmlfeature (qw[canvas websockets localstorage sessionstorage sessionhistory webworkers sharedworkers draganddrop xmlhttprequest websql]) {
        my $tmp = -1;
        $html5{$htmlfeature} = $tmp;
        #print STDERR " *** $htmlfeature $cleartext{$tmp}\n";
    }


    my $sth = $dbh->prepare_cached("SELECT username, email_addr,
                                   first_name, last_name,
                                   company_name
                                   FROM users
                            WHERE username = ?")
                or croak($dbh->errstr);

    $sth->execute($self->{autologin}->{username});


    my %user;
    while((my $line = $sth->fetchrow_hashref)) {
        $user{username} = $line->{username};
        $user{email_addr} = $line->{email_addr};
        $user{first_name} = $line->{first_name};
        $user{last_name} = $line->{last_name};
        $user{company} = $line->{company_name};
        #$user{require_password_change} = 0; # NEVER force password change
        last;
    }
    $sth->finish;
    $user{html5} = \%html5;

    my @dbRights;
    my $rightssth = $dbh->prepare_cached("SELECT * FROM users_permissions
                                         WHERE username = ?
                                         AND has_access = true
                                         ORDER BY permission_name")
            or croak($dbh->errstr);
    $rightssth->execute($user{username}) or croak($dbh->errstr);
    while((my $right = $rightssth->fetchrow_hashref)) {  ## no critic (NamingConventions::ProhibitAmbiguousNames)
        my $restrict = 0;
        foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
            if(defined($ur->{restrict}) && $right->{permission_name} eq $ur->{db}) {
                $restrict = 1;
                last;
            }
        }
        if(!$restrict) {
            push @dbRights, $right->{permission_name};
        }
    }
    $rightssth->finish;
    foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
        if(defined($ur->{restrict}) && contains($user{username}, $ur->{restrict})) {
            push @dbRights, $ur->{db};
        }
    }
    $user{rights} = \@dbRights;

    my $upsth = $dbh->prepare_cached("UPDATE users
                                     SET last_login_time = now(),
                                     last_login_ip = ?
                                     WHERE username = ?")
            or croak($dbh->errstr);
    $upsth->execute($host_addr, $user{username}) or croak($dbh->errstr);
    $upsth->finish;
    $dbh->commit;

    my $session = $self->createSession($ua, $user{username});
    $self->{server}->{modules}->{$self->{memcache}}->set($session, \%user);

    return $session;
}

sub get_switchtouser {
    my ($self, $ua) = @_;

    my $remove = $self->{switchtouser}->{webpath};
    my $targetuser = $ua->{url};
    substr($targetuser, 0, length($remove), '');

    $targetuser = decode_uri_path($targetuser);
    $targetuser =~ s/^\///g;

    my $startpage = $self->adminSwitchToUser($targetuser, $ua);
    if(!defined($startpage)) {
        return (status => 403); # Forbidden
    }

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{switchtouser}->{pagetitle},
    );

    my $template = $self->{server}->{modules}->{templates}->get("users/switchinguser", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  303,
            location => $startpage,
            type    => "text/html",
            data    => $template);
}

sub get_switchfromuser {
    my ($self, $ua) = @_;

    my $startpage = $self->adminSwitchFromUser($ua);
    if(!defined($startpage)) {
        return (status => 403); # Forbidden
    }

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{switchfromuser}->{pagetitle},
    );

    my $template = $self->{server}->{modules}->{templates}->get("users/switchinguser", 1, %webdata);
    return (status  =>  404) unless $template;
    print STDERR "***************************** $startpage\n";
    return (status  =>  303,
            location => $startpage,
            type    => "text/html",
            data    => $template);
}


sub adminSwitchToUser {
    my ($self, $username, $ua) = @_;

    my $host_addr = $ua->{remote_addr};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};
    my $viewh = $self->{server}->{modules}->{$self->{views}};

    my $session = $ua->{cookies}->{"pagecamel-session"};

    $self->updateSessionUsername($session, $username);

    my $user = $self->{server}->{modules}->{$self->{memcache}}->get($session);
    if(defined($user)) {
        $user = dbderef($user);
    }

    my @realrights = @{$user->{rights}};

    my %realuser = (
        username => $user->{username},
        first_name => $user->{first_name},
        last_name => $user->{last_name},
        email_addr => $user->{email_addr},
        company => $user->{company},
        rights => \@realrights,
    );

    $user->{realuser} = \%realuser;


    my $sth = $dbh->prepare_cached("SELECT username, email_addr,
                                   first_name, last_name,
                                   company_name
                                   FROM users
                            WHERE username = ?")
                or croak($dbh->errstr);

    $sth->execute($username);


    while((my $line = $sth->fetchrow_hashref)) {
        $user->{username} = $line->{username};
        $user->{email_addr} = $line->{email_addr};
        $user->{first_name} = $line->{first_name};
        $user->{last_name} = $line->{last_name};
        $user->{company} = $line->{company_name};
        $user->{require_password_change} = 0; # NEVER force password change
        last;
    }
    $sth->finish;

    my @dbRights;
    my $rightssth = $dbh->prepare_cached("SELECT * FROM users_permissions
                                         WHERE username = ?
                                         AND has_access = true
                                         ORDER BY permission_name")
            or croak($dbh->errstr);
    $rightssth->execute($user->{username}) or croak($dbh->errstr);
    while((my $right = $rightssth->fetchrow_hashref)) {  ## no critic (NamingConventions::ProhibitAmbiguousNames)
        my $restrict = 0;
        foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
            if(defined($ur->{restrict}) && $right->{permission_name} eq $ur->{db}) {
                $restrict = 1;
                last;
            }
        }
        if(!$restrict) {
            push @dbRights, $right->{permission_name};
        }
    }
    $rightssth->finish;
    foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
        if(defined($ur->{restrict}) && contains($user->{username}, $ur->{restrict})) {
            push @dbRights, $ur->{db};
        }
    }
    $user->{rights} = \@dbRights;

    my $upsth = $dbh->prepare_cached("UPDATE users
                                     SET last_login_time = now(),
                                     last_login_ip = ?
                                     WHERE username = ?")
            or croak($dbh->errstr);
    $upsth->execute($host_addr, $user->{username}) or croak($dbh->errstr);
    $upsth->finish;
    $dbh->commit;

    $user->{startpage} = $viewh->getstarturl(\@dbRights);
    $user->{realstartpage} = $user->{startpage};

    $self->{server}->{modules}->{$self->{memcache}}->set($session, $user);

    print STDERR "***************************** User\n";
    print STDERR Dumper($user);

    return $user->{startpage};
}

sub adminSwitchFromUser {
    my ($self, $ua) = @_;

    my $host_addr = $ua->{remote_addr};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};
    my $viewh = $self->{server}->{modules}->{$self->{views}};

    my $session = $ua->{cookies}->{"pagecamel-session"};

    my $user = $self->{server}->{modules}->{$self->{memcache}}->get($session);
    if(defined($user)) {
        $user = dbderef($user);
    }

    if(!defined($user->{realuser})) {
        return;
    }

    my $username = $user->{realuser}->{username};

    $self->updateSessionUsername($session, $username);

    my @realrights = @{$user->{realuser}->{rights}};

    $user->{username} = $user->{realuser}->{username};
    $user->{first_name} = $user->{realuser}->{first_name};
    $user->{last_name} = $user->{realuser}->{last_name};
    $user->{email_addr} = $user->{realuser}->{email_addr};
    $user->{company} = $user->{realuser}->{company};
    $user->{rights} = \@realrights;

    delete $user->{realuser};

    $user->{startpage} = $viewh->getstarturl(\@realrights);
    $user->{realstartpage} = $user->{startpage};

    $self->{server}->{modules}->{$self->{memcache}}->set($session, $user);

    print STDERR "***************************** User\n";
    print STDERR Dumper($user);

    return $user->{startpage};
}


sub preauthcleanup {
    my ($self) = @_;

    delete $self->{cookie};
    delete $self->{currentData};
    delete $self->{currentSessionID};
    $self->{isPublicUrl} = 0;
    $self->{hasBasicAuth} = 0;
    $self->{basicAuthRealm} = '';

    return;
}

sub prefilter {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};
    #warn "User requested path $webpath\n";

    foreach my $publicurl (@{$self->get_public_urls}) {
        # Make sure some (externally) registered public urls are available for
        # everyone - these may also be partial paths
        if($webpath =~ /^$publicurl/) {
            $self->{isPublicUrl} = 1;
            last;
            # Need to go through cookie checks anyway, since we need to know the user (even "guest")
            # for things like theme support even on public views
            #return;
        }
    }

    if($webpath =~ /^\/public\//) {
        $self->{isPublicUrl} = 1;
    }

    if(!$self->{isPublicUrl}) {
        my $basicauths = $self->get_basic_auths;
        foreach my $bauth (keys %{$basicauths}) {
            if($webpath =~ /^$bauth/) {
                $self->{hasBasicAuth} = 1;
                $self->{basicAuthRealm} = $basicauths->{$bauth};
                last;
            }
        }
    }

    my $session = $ua->{cookies}->{"pagecamel-session"};

    # When we allow autologin, we check if the client already has a valid session. If not, we generate one
    # on the fly for the guest user and then proceed normally with all the checks in prefilter. This should make
    # guest login completly transparent
    # Don't do this on public URL's
    if(!$self->{isPublicUrl} && defined($self->{autologin}->{username}) && $self->{autologin}->{username} ne '') {
        my $autologin = 0;
        if(!defined($session)) {
            $autologin = 1;
        } elsif(!$self->validateSession($session, $ua)) {
            $autologin = 1;
        }

        # Before we try autologin, check if we can handle basic auth. If we can, but it fails,
        # also don't do autologin
        if($autologin && $self->{hasBasicAuth}) {
            return $self->do_basic_auth($ua, $self->{basicAuthRealm});
        }

        if($autologin) {
            $session = $self->getAutologin($ua);
        }
    }

    my $user;
    if(defined($session) && $self->validateSession($session, $ua)) {
        $user = $self->{server}->{modules}->{$self->{memcache}}->get($session);
        if(defined($user)) {
            $user = dbderef($user);
        }

        if(defined($user)) {
            # Check if the user tries to open something he's not allowed to
            if(!$self->{isPublicUrl}) {
                foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
                    next if(!defined($ur->{path}));
                    my $checkpath = "^" .  $ur->{path};
                    if(($webpath =~ /$checkpath/ && !contains($ur->{db}, $user->{rights}))) {
                        return (status      => 303,
                                location    => $self->{login}->{webpath},
                                type        => "text/html",
                                data         => "<html><body><h1>Please login.</h1><br>" .
                                                "If you are not automatically redirected, click " .
                                                "<a href=\"" . $self->{login}->{webpath} . "\">here</a>.</body></html>",
                                );
                    }
                }
            }
            $self->{cookie} = $self->create_cookie($ua,
                                                   "name" => "pagecamel-session",
                                                   "value" => $session,
                                                   "expires" => $self->{expires},
                                                   "httponly" => 1,
                                                    "secure" => $self->{httpsonlycookies},
                                                   "location" => '/',
                                                   "samesite" => 'strict',
                                                );
            my %currentData = (sessionid    =>  $session,
                               user         =>  $user->{username},
                               email_addr    =>    $user->{email_addr},
                               first_name    =>    $user->{first_name},
                               last_name    =>    $user->{last_name},
                               company      =>  $user->{company},
                               html5        => $user->{html5},
                               rights       => $user->{rights},
                               activeurl    => $webpath,
                               require_password_change  => $user->{require_password_change},
                              );

            if(defined($user->{realuser})) {
                $currentData{hasrealuser} = 1;
            } else {
                $currentData{hasrealuser} = 0;
            }
            $self->{currentData} = \%currentData;
        } else {
            #warn "No user session data for $session\n";
        }
    } else {
        #warn "Invalid session cookie\n";
    }

    if($self->{isPublicUrl}) {
        # No blocking of access without cookie on public URLs
        return;
    }

    if(defined($self->{cookie})) {
        # Refresh the session
        $self->{server}->sessionrefresh($self->{currentData}->{sessionid});
        $self->{currentSessionID} = $session;

        # Ok, now we need to check if we must redirect the user to the password change mask. This happens in the case where the user
        # got redirected before but did try to navigate to another mask instead
        if($user->{require_password_change} && $webpath ne $self->{pwchange} && $webpath ne $self->{sessionrefresh}->{webpath}) {
            return (status      => 303,
                    location    => $self->{pwchange},
                    type        => "text/html",
                    data         => "<html><body><h1>Please change your password</h1><br>" .
                                    "If you are not automatically redirected, click " .
                                    "<a href=\"" . $self->{pwchange} . "\">here</a>.</body></html>",
                    );
        }


        return; # No redirection
    } else {
        # Need to login (in case of trying a session refresh, sen special text to enable
        # correct javascript handling)
        if($webpath ne $self->{sessionrefresh}->{webpath}) {
            return (status      => 303,
                    location    => $self->{login}->{webpath},
                    type        => "text/html",
                    data         => "<html><body><h1>Please login</h1><br>" .
                                    "If you are not automatically redirected, click " .
                                    "<a href=\"" . $self->{login}->{webpath} . "\">here</a>.</body></html>",
                    );
        } else {
            return (status  => 200,
                    type    => 'text/plain',
                    data    => 'INVALID_SESSION',
                    );
        }
    }
}

sub genBasicAuthRequest {
    my ($self, $realm) = @_;

    return (
        status  => 401,
        "WWW-Authenticate"  => 'Basic realm="' . $realm . '"',
    );
}

sub do_basic_auth {
    my ($self, $ua, $realm) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    if(!defined($ua->{headers}->{Authorization}) || $ua->{headers}->{Authorization} !~ /^Basic\ /) {
        return $self->genBasicAuthRequest($realm);
    }

    my $enc = $ua->{headers}->{Authorization};
    $enc =~ s/^Basic\ //;
    my $dec = decode_base64($enc);
    my ($dynuser, $dynpass);
    if(defined($dec) && $dec ne '' && $dec =~ /\:/) {
        ($dynuser, $dynpass) = split/\:/, $dec;
    }

    if(!defined($dynuser) || !defined($dynpass) || $dynuser eq '' || $dynpass eq '') {
        return $self->genBasicAuthRequest($realm);
    }

    # Check credentials (try database cache for speed first)
    my $authcookie = sha256_hex($self->{basicauth_prefix_salt} . $dynuser . $self->{basicauth_middle_salt} . $dynpass . $self->{basicauth_postfix_salt});
    my $cacheselsth = $dbh->prepare_cached("SELECT * from users_basicauthcache
                                            WHERE authcookie = ? and valid_until >= now()
                                            LIMIT 1")
                or croak($dbh->errstr);

    my $cacheinsth = $dbh->prepare_cached("INSERT INTO users_basicauthcache (authcookie) VALUES (?)")
                or croak($dbh->errstr);

    my $pwok = 0;
    if(!$cacheselsth->execute($authcookie)) {
        $dbh->rollback;
    } else {
        while((my $line = $cacheselsth->fetchrow_hashref)) {
            $pwok = 1;
        }
        $cacheselsth->finish;
        $dbh->rollback;
    }

    if(!$pwok) {
        $pwok = verify_password($dbh, $dynuser, $dynpass);

        if($pwok) {
            if($cacheinsth->execute($authcookie)) {
                $dbh->commit;
            }
        }
    }
    $dbh->rollback;

    if(!$pwok) {
        return $self->genBasicAuthRequest($realm);
    }

    # Now check if the user has permissions for this path
    my $permok = 0;
    my $webpath = $ua->{url};
    my $requiredpermission = '';
    foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
        next if(!defined($ur->{path}));
        my $checkpath = "^" .  $ur->{path};
        if($webpath =~ /$checkpath/) {
            $requiredpermission = $ur->{db};
            last;
        }
    }

    if($requiredpermission eq '') {
        return (status => 500,
                statustext => 'Internal Server Error (Permission Snafu)',
        );
    }

    my $selsth = $dbh->prepare_cached("SELECT count(*) FROM users_permissions
                                       WHERE username = ?
                                       AND permission_name = ?
                                       AND has_access = true")
            or croak($dbh->errstr);
    if(!$selsth->execute($dynuser, $requiredpermission)) {
        $dbh->rollback;
        return (status => 500,
                statustext => 'Internal Server Error (DB)',
        );
    }
    my ($count) = $selsth->fetchrow_array;
    $selsth->finish;
    $dbh->rollback;

    if($count) {
        $permok = 1;
    }

    if(!$permok) {
        return $self->genBasicAuthRequest($realm);
    }

    $reph->auditlog($self->{modname}, "Login success (basic auth) $dynuser OK", $dynuser);

    return;

}

sub password_changed {
    my ($self, $ua) = @_;

    my $session = $ua->{cookies}->{"pagecamel-session"};
    my $user;
    if(defined($session) && $self->validateSession($session, $ua)) {
        $user = $self->{server}->{modules}->{$self->{memcache}}->get($session);
        if(defined($user)) {
            $user = dbderef($user);
        }
    }

    if($user->{require_password_change}) {
        $user->{startpage} = $user->{realstartpage};
        $self->{redirect_to} = $user->{startpage};
    }

    $user->{require_password_change} = 0;

    $self->{server}->{modules}->{$self->{memcache}}->set($session, $user);


    return;
}

sub postfilter {
    my ($self, $ua, $header, $result) = @_;

    # Just add the cookie to the header
    if(defined($self->{cookie})) {
        $header->{-cookie} = $self->{cookie};
        $self->extend_header($result, "Vary", "Cookie");
        delete $self->{cookie}; # Don't leak cookie next time, if for some reason prefilter is never called (for example on path redirection prefiltering)
    }

    if(defined($self->{redirect_to})) {;
        $result->{status} = 303;
        $result->{type} = "text/plain";
        $result->{data} = "Please wait...";
        $result->{location} = $self->{redirect_to};
        delete $self->{redirect_to};
    }

    return;
}

sub get_defaultwebdata {
    my ($self, $webdata) = @_;

    if(defined($self->{currentData})) {
        $webdata->{userData} = $self->{currentData};
    }
    $webdata->{isPublicUrl} = $self->{isPublicUrl};
    return;
}

sub createSession {
    my ($self, $ua, $username) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $validChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.+-";
    my $host_addr = $ua->{remote_addr};

    my $randchars = '';
    for(1..25) {
        $randchars .= substr($validChars, int(rand(length($validChars))), 1);
    }
    my $session = "3SESSION" . sha256_hex(time() . $randchars . $host_addr);


    $session .= sha256_hex($host_addr);
    my $userAgent = $ua->{headers}->{'User-Agent'} || '--unknown--';
    my ($simpleUA, $batbot) = simplifyUA($userAgent);

    my $sth = $dbh->prepare_cached("INSERT INTO sessions
                                    (sid, username, client_ip, useragent, useragent_simplified, logintime, valid_until)
                                    VALUES (?,?,?,?,?, now(), (now() + interval '10 minutes'))")
            or croak($dbh->errstr);

    if(!$sth->execute($session, $username, $host_addr, $userAgent, $simpleUA)) {
        $dbh->rollback;
        return;
    }

    $dbh->commit;

    $self->{currentSessionID} = $session;
    $self->{server}->user_login($username, $session);

    return $session;
}

sub deleteSession {
    my ($self, $session) = @_;

    $self->{server}->user_logout($session);
    #$self->{server}->{modules}->{$self->{memcache}}->delete($session);
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    # CALL ON_LOGOUT

    my $sth = $dbh->prepare_cached("DELETE FROM sessions
                                   WHERE sid = ?")
            or croak($dbh->errstr);

    if(!$sth->execute($session)) {
        $dbh->rollback;
    } else {
        $dbh->commit;
    }

    $memh->delete($session);

    # Delete sessionsettings for this session
    my @keys = $memh->clacks_keylist();
    #my $searchkey = 'SessionSettings::' . $session . '::';
    my $searchkey = 'SessionSettings::' . $session;
    foreach my $key (@keys) {
        if($key =~ /^$searchkey/) {
            $memh->delete($key);
        }
    }


    return;
}

sub updateSessionUsername {
    my ($self, $session, $username) = @_;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $sth = $dbh->prepare_cached("UPDATE sessions SET username = ?
                                   WHERE sid = ?")
            or croak($dbh->errstr);

    if(!$sth->execute($username, $session)) {
        $dbh->rollback;
    } else {
        $dbh->commit;
    }

    return;
}

sub validateSession {
    my ($self, $session, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    if(!defined($session) || $session eq "NONE") {
        #warn "No session cookie: $session\n";
        return 0; # Invalid session
    }

    my $host_addr = $ua->{remote_addr};
    my $userAgent = $ua->{headers}->{'User-Agent'} || '--unknown--';

    my @stales;

    # First, find all stale sessions
    {
        my $stalesth = $dbh->prepare_cached("SELECT sid FROM sessions
                                          WHERE valid_until < now()")
                or croak($dbh->errstr);
        $stalesth->execute or croak($dbh->errstr); # if we can not check if the session is
                                                 # valid, we are really, really screwed!

        while((my @stale = $stalesth->fetchrow_array)) {
            push @stales, $stale[0];
        }
        $stalesth->finish;
    }

if(0) { # Disabled for testing
    # If a session ID is beeing spoofed from different IP or browser we
    # can detect that. Invalidate that session
    my $fakesth = $dbh->prepare_cached("SELECT sid, client_ip, useragent FROM sessions
                                      WHERE sid = ?
                                      AND (client_ip != ?
                                           OR useragent != ?)")
            or croak($dbh->errstr);
    $fakesth->execute($session, $host_addr, $userAgent)
            or croak($dbh->errstr); # if we can not check if the session is
                                    # valid, we are really, really screwed!

    while((my @fake = $fakesth->fetchrow_array)) {
        if($fake[2] ne $userAgent) {
            print STDERR "Client changed userAgent string from:\n    $userAgent\nto\n    $fake[2]\n";
            if($userAgent =~ /MSIE\ 8\.0/ && $fake[2] =~ /MSIE\ 7\.0/) {
                # Our office team messed up big time in upgrading IE7 to IE 8. When the
                # browser opens a new window, it suddenly loads the IE 7.0 renderer into
                # a IE 8.0 window, changing the userAgent string.
                # Reverse this one version number change and see if the strings compare then.
                # If so, do not invalidate the session.
                #
                # This undermines security a but. But using IE does this anyway. And
                # it's not really my problem, it's the office IT team that messed up..
                $fake[2] =~ s/MSIE\ 7\.0/MSIE 8.0/g;
                if($fake[2] eq $userAgent) {
                    # Yeah, probably just found a broken IE 8.0 installation
                    print STDERR "Detected major Office IT f.ck.p, temporarly accepting broken browser as valid.\n";
                    next;
                }

            }
        }

        # !!!!!!!! WARNING !!!!!!! CURRENTLY userAgent check is disabled due to multiple problems!!!!!!!
        if($fake[2] ne $userAgent && $fake[1] eq $host_addr) {
            print STDERR "   !!! USERAGENT CHECK DISABLED !!!\n";
            next;
        }
        # !!!!!!!! WARNING !!!!!!! CURRENTLY userAgent check is disabled due to multiple problems!!!!!!!

        push @stales, $fake[0];
        if($fake[1] ne $host_addr) {
            print STDERR "Client changed IP from $host_addr to $fake[1]!\n";
        }
        print STDERR "Invalidating this session!!!\n";
    }
    $fakesth->finish;
}
    $dbh->commit;

    foreach my $stale (@stales) {
        $self->deleteSession($stale);
    }


    my $countsth = $dbh->prepare_cached("SELECT count(*) FROM sessions
                                        WHERE sid = ?
                                        AND client_ip = ?")
            or croak($dbh->errstr);

    $countsth->execute($session, $host_addr)
            or croak($dbh->errstr); # if we can not check if the session is
                                    # valid, we are really, really screwed!



    my ($count) = $countsth->fetchrow_array;
    $countsth->finish;
    $dbh->commit;

    if(!defined($count) || $count != 1) {
        return 0;
    }

    $self->refreshSession($session, $ua);
    return 1;

}

sub refreshSession {
    my ($self, $session, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    $memh->clacks_set('Login::Sessionrefresh', $session);

    return 1;

}

sub get_sessionid {
    my ($self) = @_;

    return $self->{currentSessionID};
}

sub get_sessionrefresh {
    my ($self, $ua) = @_;

    if($ua->{method} eq 'POST') {
        # Beacon
        return (
            status => 204, # No content
             "Cache-Control" => 'no-cache, no-store',
            "__do_not_log_to_accesslog" => 1,
        );
    }

    # we just return the current time, everything else is done by prefilter ;-)
    return (status      => 200,
        type        => "text/plain",
        data         => getISODate(),
        "Cache-Control" => 'no-cache, no-store',
        "__do_not_log_to_accesslog" => 1,
    );
}

sub firewall_log_loginfailure() {
    my ($self, $ua) = @_;

    if($self->{disable_firewall}) {
        return;
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $insth = $dbh->prepare_cached("INSERT INTO firewall_loginerrors (ip_address) VALUES (?)")
            or croak($dbh->errstr);
    if($insth->execute($ua->{remote_addr})) {
        $dbh->commit;
    } else {
        $dbh->rollback;
    }
    return;

}

sub firewall_check_loginfailure() {
    my ($self, $ua) = @_;

    if($self->{disable_firewall}) {
        return 1;
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $delsth = $dbh->prepare_cached("DELETE FROM firewall_loginerrors
                                       WHERE logtime + interval '" . $self->{login}->{fail_window} . " seconds' < now()")
            or croak($dbh->errstr);

    my $selsth = $dbh->prepare_cached("SELECT count(*) AS failcount FROM firewall_loginerrors
                                       WHERE ip_address = ?")
            or croak($dbh->errstr);

    if($delsth->execute) {
        $dbh->commit;
    } else {
        $dbh->rollback;
    }

    if(!$selsth->execute($ua->{remote_addr})) {
        $dbh->rollback;
        return 0;
    }
    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    $dbh->commit;

    if($line->{failcount} < $self->{login}->{fail_max}) {
        return 1;
    } else {
        return 0;
    }
}

1;
__END__

=head1 NAME

PageCamel::Web::Users::Login -

=head1 SYNOPSIS

  use PageCamel::Web::Users::Login;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 crossregister



=head2 get_logout



=head2 get_login



=head2 getAutologin



=head2 preauthcleanup



=head2 prefilter



=head2 password_changed



=head2 postfilter



=head2 get_defaultwebdata



=head2 createSession



=head2 deleteSession



=head2 validateSession



=head2 refreshSession



=head2 get_sessionid



=head2 get_sessionrefresh



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
