#
# Copyright (C) 1998 Ken MacLeod
# See the file COPYING for distribution terms.
#
# $Id: rpc-client.pl,v 1.2 1998/07/30 15:52:32 ken Exp $
#

=head1 NAME

rpc-client -- example XML RPC client

=head1 SYNOPSIS

 rpc-client URL METHOD ["ARGLIST"]

=head1 DESCRIPTION

`C<rpc-client>' exercises an XML RPC server.  I<URL> is the URL of the
RPC server to contact, including a path if necessary, like `C</RPC2>'.
I<METHOD> is the procedure to call on the remote server.

`C<"I<ARGLIST>">' is the argument list to be sent to the remote server.
I<ARGLIST> may include Perl array and hash constructors and should
always be quoted.

The result returned from the XML RPC server is displayed using Perl's
`dumpvar.pl' utility, showing the internal structure of the objects
returned from the server.

=head1 EXAMPLES

 rpc-client http://betty.userland.com/RPC2 examples.getStateName "41"

 rpc-client http://betty.userland.com/RPC2 \
   examples.getStateList "[12, 28, 33, 39, 46]"

 rpc-client http://betty.userland.com/RPC2 \
   examples.getStateStruct "{state1 => 18, state2 => 27, state3 => 48}"

=cut

use Frontier::Client;

die "usage: rpc-client URL METHOD [\"ARGLIST\"]\n"
    if ($#ARGV != 1 && $#ARGV != 2);

my $url = shift @ARGV;
my $method = shift @ARGV;
my $arglist = shift @ARGV;

$server = new Frontier::Client url => $url;

my @arglist;
eval "\@arglist = ($arglist)";

$result = $server->call ($method, @arglist);

require 'dumpvar.pl';
dumpvar ('main', 'result');
