#
# Copyright (C) 1998 Ken MacLeod
# Frontier::Client is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id: Client.pm,v 1.5 1999/04/13 19:43:46 kmacleod Exp $
#

# NOTE: see Net::pRPC for a Perl RPC implementation

use strict;

package Frontier::Client;
use Frontier::RPC2;
use LWP::UserAgent;
use HTTP::Request;

use vars qw{$AUTOLOAD};

sub new {
    my $class = shift; my %args = @_;

    my $self = bless \%args, $class;

    die "Frontier::RPC::new: no url defined\n"
	if !defined $self->{'url'};

    $self->{'ua'} = LWP::UserAgent->new;
    $self->{'rq'} = HTTP::Request->new (POST => $self->{'url'});
    $self->{'rq'}->header('Content-Type' => 'text/xml');
    $self->{'enc'} = Frontier::RPC2->new;

    return $self;
}

sub call {
    my $self = shift;

    my $text = $self->{'enc'}->encode_call(@_);

    $self->{'rq'}->content($text);

    my $response = $self->{'ua'}->request($self->{'rq'});

    if (substr($response->code, 0, 1) ne '2') {
	die $response->status_line . "\n";
    }

    my $content = $response->content;
    # FIXME bug in Frontier's XML
    $content =~ s/(<\?XML\s+VERSION)/\L$1\E/;
    my $result = $self->{'enc'}->decode($content);

    if ($result->{'type'} eq 'fault') {
	die "Fault returned from XML RPC Server, fault code " . $result->{'value'}[0]{'faultCode'} . ": "
	    . $result->{'value'}[0]{'faultString'} . "\n";
    }

    return $result->{'value'}[0];
}

# shortcuts
sub base64 {
    my $self = shift;

    return Frontier::RPC2::Base64->new(@_);
}

sub boolean {
    my $self = shift;

    return Frontier::RPC2::Boolean->new(@_);
}

sub date_time {
    my $self = shift;

    return Frontier::RPC2::DateTime::ISO8601->new(@_);
}

# something like this could be used to get an effect of
#
#     $server->examples_getStateName(41)
#
# instead of
#
#     $server->call('examples.getStateName', 41)
#
# for Frontier's
#
#     [server].examples.getStateName 41
#
# sub AUTOLOAD {
#     my ($pkg, $method) = ($AUTOLOAD =~ m/^(.*::)(.*)$/);
#     return if $method eq 'DESTROY';
# 
#     $method =~ s/__/=/g;
#     $method =~ tr/_=/._/;
# 
#     splice(@_, 1, 0, $method);
# 
#     goto &call;
# }

=head1 NAME

Frontier::Client - issue Frontier XML RPC requests to a server

=head1 SYNOPSIS

 use Frontier::Client;

 $server = Frontier::Client->new(url => $url);

 $result = $server->call($method, @args);

 $boolean = $server->boolean($value);
 $date_time = $server->date_time($value);
 $base64 = $server->base64($value);

 $value = $boolean->value;
 $value = $date_time->value;
 $value = $base64->value;

=head1 DESCRIPTION

I<Frontier::Client> objects record the URL of the server to connect
to.  The `C<call>' method is then used to forward procedure calls to
the server, either returning the value returned by the procedure or
failing with exception.

The methods `C<boolean>', `C<date_time>', and `C<base64>' create and
return XML-RPC-specific datatypes that can be passed to the server.
Results from servers may also contain these datatypes.  The
corresponding package names (for use with `C<ref()>', for example) are
`C<Frontier::RPC2::Boolean>', `C<Frontier::RPC2::DateTime::ISO8601>',
and `C<Frontier::RPC2::Base64>'.

The value of boolean, date/time, and base64 data are returned using
the `C<value>' method.

=head1 SEE ALSO

perl(1), Frontier::RPC2(3)

<http://www.scripting.com/frontier5/xml/code/rpc.html>

=head1 AUTHOR

Ken MacLeod <ken@bitsko.slc.ut.us>

=cut

1;
