#
# Copyright (C) 1998, 1999 Ken MacLeod
# Frontier::RPC is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id: RPC2.pm,v 1.5 1999/01/28 21:11:41 kmacleod Exp $
#

# NOTE: see Storable for marshalling.

use strict;

package Frontier::RPC2;
use XML::Parser;

use vars qw{%scalars %char_entities};

%char_entities = (
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    '"' => '&quot;',
);

# FIXME I need a list of these
%scalars = (
    'base64' => 1,
    'boolean' => 1,
    'dateTime.iso8601' => 1,
    'double' => 1,
    'int' => 1,
    'i4' => 1,
    'string' => 1,
);

sub new {
    my $class = shift; my %args = @_;

    return bless \%args, $class;
}

sub encode_call {
    my $self = shift; my $proc = shift;

    my @text;
    push @text, <<EOF;
<?xml version="1.0"?>
<methodCall>
<methodName>$proc</methodName>
<params>
EOF

    push @text, $self->_array([@_], 1);

    push @text, <<EOF;
</params>
</methodCall>
EOF

    return join('', @text);
}

sub encode_response {
    my $self = shift;

    my @text;
    push @text, <<EOF;
<?xml version="1.0"?>
<methodResponse>
<params>
EOF

    push @text, $self->_array([@_], 1);

    push @text, <<EOF;
</params>
</methodResponse>
EOF

    return join('', @text);
}

sub encode_fault {
    my $self = shift; my $code = shift; my $message = shift;

    my @text;
    push @text, <<EOF;
<?xml version="1.0"?>
<methodResponse>
<fault>
EOF

    push @text, $self->_array([ {faultCode => $code, faultString => $message} ], 0);

    push @text, <<EOF;
</fault>
</methodResponse>
EOF

    return join('', @text);
}

sub serve {
    my $self = shift; my $xml = shift; my $methods = shift;

    my $call;
    # FIXME bug in Frontier's XML
    $xml =~ s/(<\?XML\s+VERSION)/\L$1\E/;
    eval { $call = $self->decode($xml) };

    if ($@) {
	return $self->encode_fault(1, "error decoding RPC.\n" . $@);
    }

    if ($call->{'type'} ne 'call') {
	return $self->encode_fault(2,"expected RPC \`methodCall', got \`$call->{'type'}'\n");
    }

    my $method = $call->{'method_name'};
    if (!defined $methods->{$method}) {
        return $self->encode_fault(3, "no such method \`$method'\n");
    }

    my $result;
    my $eval = eval { $result = &{ $methods->{$method} }(@{ $call->{'value'} }) };
    if ($@) {
	return $self->encode_fault(4, "error executing RPC \`$method'.\n" . $@);
    }

    my $xml = $self->encode_response($result);
    return $xml;
}

sub _array {
    my $self = shift; my $array = shift; my $is_param = shift;

    my $param_s = $is_param ? "<param>" : "";
    my $param_e = $is_param ? "</param>" : "";

    my @text;

    my $arg;
    foreach $arg (@$array) {
	my $ref = ref($arg);
	if (!$ref) {
	    push (@text,
		  "$param_s<value>",
		  $self->_scalar ($arg),
		  "</value>$param_e\n");
        } elsif ($ref eq 'ARRAY') {
	    push (@text,
		  "$param_s<value><array><data>\n",
		  $self->_array($arg),
		  "</data></array></value>$param_e\n");
	} elsif ($ref eq 'HASH') {
	    push @text, "$param_s<value><struct>\n";
	    my ($key, $value);
	    while (($key, $value) = each %$arg) {
		push (@text,
		      "<member><name>$key</name><value>",
		      $self->_scalar($value),
		      "</value></member>\n");
	    }
	    push @text, "</struct></value>$param_e\n";
	} elsif ($ref eq 'Frontier::RPC2::Boolean') {
	    push @text, "$param_s<value><boolean>", $arg->repr, "</boolean></value>$param_e\n";
	} elsif ($ref eq 'Frontier::RPC2::DateTime::ISO8601') {
	    push @text, "$param_s<value><dateTime.iso8601>", $arg->repr, "</dateTime.iso8601></value>$param_e\n";
	} elsif ($ref eq 'Frontier::RPC2::Base64') {
	    push @text, "$param_s<value><base64>", $arg->repr, "</base64></value>$param_e\n";
	} else {
	    die "can't convert \`$arg' to XML\n";
	}
    }

    return @text;
}

sub _scalar {
    my $self = shift; my $value = shift;

    if ($value == 0 && $value ne "0") {
	$value =~ s/([&<>\"])/$char_entities{$1}/ge;
	return ("<string>$value</string>");
    } elsif ($value =~ /^[+-]?\d+$/) {
	return ("<i4>$value</i4>");
    } else {
	return ("<double>$value</double>");
    }
}

sub decode {
    my $self = shift; my $string = shift;

    $self->{'parser'} = new XML::Parser Style => ref($self);
    return $self->{'parser'}->parsestring($string);
}


######################################################################
###
### XML::Parser callbacks
###

sub die {
    my $parser = shift; my $message = shift;

    die $message
	. "at line " . $parser->current_line
        . " column " . $parser->current_column . "\n";
}

sub init {
    my $self = shift;

    $self->{'rpc_state'} = [];
    $self->{'rpc_container'} = [ [] ];
    $self->{'rpc_member_name'} = [];
    $self->{'rpc_type'} = undef;
    $self->{'rpc_args'} = undef;
}

# FIXME this state machine wouldn't be necessary if we had a DTD.
sub start {
    my $self = shift; my $tag = shift;

    my $state = $self->{'rpc_state'}[-1];

    if (!defined $state) {
	if ($tag eq 'methodCall') {
	    $self->{'rpc_type'} = 'call';
	    push @{ $self->{'rpc_state'} }, 'want_method_name';
	} elsif ($tag eq 'methodResponse') {
	    push @{ $self->{'rpc_state'} }, 'method_response';
	} else {
	    Frontier::RPC2::die($self, "unknown RPC type \`$tag'\n");
	}
    } elsif ($state eq 'want_method_name') {
	Frontier::RPC2::die($self, "wanted \`methodName' tag, got \`$tag'\n")
	    if ($tag ne 'methodName');
	push @{ $self->{'rpc_state'} }, 'method_name';
    } elsif ($state eq 'method_response') {
	if ($tag eq 'params') {
	    $self->{'rpc_type'} = 'response';
	    push @{ $self->{'rpc_state'} }, 'params';
	} elsif ($tag eq 'fault') {
	    $self->{'rpc_type'} = 'fault';
	    push @{ $self->{'rpc_state'} }, 'want_value';
	}
    } elsif ($state eq 'want_params') {
	Frontier::RPC2::die($self, "wanted \`params' tag, got \`$tag'\n")
	    if ($tag ne 'params');
	push @{ $self->{'rpc_state'} }, 'params';
    } elsif ($state eq 'params') {
	Frontier::RPC2::die($self, "wanted \`param' tag, got \`$tag'\n")
	    if ($tag ne 'param');
	push @{ $self->{'rpc_state'} }, 'want_param_name_or_value';
    } elsif ($state eq 'want_param_name_or_value') {
	if ($tag eq 'value') {
	    push @{ $self->{'rpc_state'} }, 'value';
	} elsif ($tag eq 'name') {
	    push @{ $self->{'rpc_state'} }, 'param_name';
	} else {	    
	    Frontier::RPC2::die($self, "wanted \`value' or \`name' tag, got \`$tag'\n");
	}
    } elsif ($state eq 'param_name') {
	Frontier::RPC2::die($self, "wanted parameter name data, got tag \`$tag'\n");
    } elsif ($state eq 'want_value') {
	Frontier::RPC2::die($self, "wanted \`value' tag, got \`$tag'\n")
	    if ($tag ne 'value');
	push @{ $self->{'rpc_state'} }, 'value';
    } elsif ($state eq 'value') {
	if ($tag eq 'array') {
	    push @{ $self->{'rpc_container'} }, [];
	    push @{ $self->{'rpc_state'} }, 'want_data';
	} elsif ($tag eq 'struct') {
	    push @{ $self->{'rpc_container'} }, {};
	    push @{ $self->{'rpc_member_name'} }, undef;
	    push @{ $self->{'rpc_state'} }, 'struct';
	} elsif ($scalars{$tag}) {
	    push @{ $self->{'rpc_state'} }, 'cdata';
	} else {
	    Frontier::RPC2::die($self, "wanted a data type, got \`$tag'\n");
	}
    } elsif ($state eq 'want_data') {
	Frontier::RPC2::die($self, "wanted \`data', got \`$tag'\n")
	    if ($tag ne 'data');
	push @{ $self->{'rpc_state'} }, 'array';
    } elsif ($state eq 'array') {
	Frontier::RPC2::die($self, "wanted \`value' tag, got \`$tag'\n")
	    if ($tag ne 'value');
	push @{ $self->{'rpc_state'} }, 'value';
    } elsif ($state eq 'struct') {
	Frontier::RPC2::die($self, "wanted \`member' tag, got \`$tag'\n")
	    if ($tag ne 'member');
	push @{ $self->{'rpc_state'} }, 'want_member_name';
    } elsif ($state eq 'want_member_name') {
	Frontier::RPC2::die($self, "wanted \`name' tag, got \`$tag'\n")
	    if ($tag ne 'name');
	push @{ $self->{'rpc_state'} }, 'member_name';
    } elsif ($state eq 'member_name') {
	Frontier::RPC2::die($self, "wanted data, got tag \`$tag'\n");
    } elsif ($state eq 'cdata') {
	Frontier::RPC2::die($self, "wanted data, got tag \`$tag'\n");
    } else {
	Frontier::RPC2::die($self, "internal error, unknown state \`$state'\n");
    }
}

sub end {
    my $self = shift; my $tag = shift;

    my $state = pop @{ $self->{'rpc_state'} };

    if ($state eq 'cdata') {
	my $value = $self->{'rpc_text'};
	if ($tag eq 'base64') {
	    $value = Frontier::RPC2::Base64->new($value);
	} elsif ($tag eq 'boolean') {
	    $value = Frontier::RPC2::Boolean->new($value);
	} elsif ($tag eq 'dateTime.iso8601') {
	    $value = Frontier::RPC2::DateTime::ISO8601->new($value);
	}
	$self->{'rpc_value'} = $value;
    } elsif ($state eq 'member_name') {
	$self->{'rpc_member_name'}[-1] = $self->{'rpc_text'};
	$self->{'rpc_state'}[-1] = 'want_value';
    } elsif ($state eq 'method_name') {
	$self->{'rpc_method_name'} = $self->{'rpc_text'};
	$self->{'rpc_state'}[-1] = 'want_params';
    } elsif ($state eq 'struct') {
	$self->{'rpc_value'} = pop @{ $self->{'rpc_container'} };
	pop @{ $self->{'rpc_member_name'} };
    } elsif ($state eq 'array') {
	$self->{'rpc_value'} = pop @{ $self->{'rpc_container'} };
    } elsif ($state eq 'value') {
	my $container = $self->{'rpc_container'}[-1];
	if (ref($container) eq 'ARRAY') {
	    push @$container, $self->{'rpc_value'};
	} elsif (ref($container) eq 'HASH') {
	    $container->{ $self->{'rpc_member_name'}[-1] } = $self->{'rpc_value'};
	}
    }
}

sub char {
    my $self = shift; my $text = shift;

    $self->{'rpc_text'} = $text;
}

sub proc {
}

sub final {
    my $self = shift;

    $self->{'rpc_value'} = pop @{ $self->{'rpc_container'} };
    
    return {
	value => $self->{'rpc_value'},
	type => $self->{'rpc_type'},
	method_name => $self->{'rpc_method_name'},
    };
}

package Frontier::RPC2::DataType;

sub new {
    my $type = shift; my $value = shift;

    return bless \$value, $type;
}

# `repr' returns the XML representation of this data, which may be
# different [in the future] from what is returned from `value'
sub repr {
    my $self = shift;

    return $$self;
}

# sets or returns the usable value of this data
sub value {
    my $self = shift;
    @_ ? ($$self = shift) : $$self;
}

package Frontier::RPC2::Base64;

use vars qw{@ISA};
@ISA = qw{Frontier::RPC2::DataType};

package Frontier::RPC2::Boolean;

use vars qw{@ISA};
@ISA = qw{Frontier::RPC2::DataType};

package Frontier::RPC2::DateTime::ISO8601;

use vars qw{@ISA};
@ISA = qw{Frontier::RPC2::DataType};

=head1 NAME

Frontier::RPC2 - encode/decode RPC2 format XML

=head1 SYNOPSIS

 use Frontier::RPC2;

 $coder = Frontier::RPC2->new;

 $xml_string = $coder->encode_call($method, @args);
 $xml_string = $coder->encode_response($result);
 $xml_string = $coder->encode_fault($code, $message);

 $call = $coder->decode($xml_string);

 $response_xml = $coder->serve($request_xml, $methods);

=head1 DESCRIPTION

I<Frontier::RPC2> encodes and decodes XML RPC calls.

=over 4

=item $coder = Frontier::RPC2->new()

Create a new encoder/decoder.

=item $xml_string = $coder->encode_call($method, @args)

`C<encode_call>' converts a method name and it's arguments into an
RPC2 `C<methodCall>' element, returning the XML fragment.

=item $xml_string = $coder->encode_response($result)

`C<encode_response>' converts the return value of a procedure into an
RPC2 `C<methodResponse>' element containing the result, returning the
XML fragment.

=item $xml_string = $coder->encode_fault($code, $message)

`C<encode_fault>' converts a fault code and message into an RPC2
`C<methodResponse>' element containing a `C<fault>' element, returning
the XML fragment.

=item $call = $coder->decode($xml_string)

`C<decode>' converts an XML string containing an RPC2 `C<methodCall>'
or `C<methodResponse>' element into a hash containing three members,
`C<type>', `C<value>', and `C<method_name>'.  `C<type>' is one of
`C<call>', `C<response>', or `C<fault>'.  `C<value>' is array
containing the parameters or result of the RPC.  For a `C<call>' type,
`C<value>' contains call's parameters and `C<method_name>' contains
the method being called.  For a `C<response>' type, the `C<value>'
array contains call's result.  For a `C<fault>' type, the `C<value>'
array contains a hash with the two members `C<faultCode>' and
`C<faultMessage>'.

=item $response_xml = $coder->serve($request_xml, $methods)

`C<serve>' decodes `C<$request_xml>', looks up the called method name
in the `C<$methods>' hash and calls it, and then encodes and returns
the response as XML.

=back

=head1 SEE ALSO

perl(1), Frontier::Daemon(3), Frontier::Client(3)

<http://www.scripting.com/frontier5/xml/code/rpc.html>

=head1 AUTHOR

Ken MacLeod <ken@bitsko.slc.ut.us>

=cut

1;
