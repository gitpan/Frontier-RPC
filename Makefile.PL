#
# Copyright (C) 1998 Ken MacLeod
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# $Id: Makefile.PL,v 1.1.1.1 1998/04/14 03:50:48 ken Exp $
#

$VERSION = '0.03';

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'Frontier::RPC',
    'VERSION_FROM' => 'Makefile.PL',
    dist        => {'COMPRESS'  => 'gzip', 'SUFFIX'    => '.gz'},
);
